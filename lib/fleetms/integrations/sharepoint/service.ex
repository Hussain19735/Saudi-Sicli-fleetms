defmodule Fleetms.Integrations.SharePoint.Service do
  @moduledoc """
  Authorization boundary for SharePoint repository operations.

  The actor must come from the authenticated server session. For updates, target
  scope MUST be loaded from the existing SharePoint record on the server; never
  construct it from browser parameters. Create scope must be validated against
  trusted server-side relationships before calling this module.

  Project, city, and vehicle relationship fields are immutable through the
  generic update operation. Reassignment requires a dedicated operation with
  explicit authorization for both the old and new scope.
  """

  alias Fleetms.Integrations.SharePoint.{AccessPolicy, Repository}

  @scope_field_names ~w(projectid project_id cityid city_id vehicleid vehicle_id)

  @spec authorize(map(), atom(), map()) :: :ok | {:error, :forbidden}
  def authorize(actor, action, trusted_target) do
    AccessPolicy.authorize(actor, action, trusted_target)
  end

  @spec create(map(), term(), atom(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def create(settings, actor, :approval_records, fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    with {:ok, approval_action} <- approval_action(fields),
         :ok <- authorize(actor, approval_action, trusted_target),
         {:ok, scoped_fields} <- stamp_trusted_scope(fields, trusted_target),
         :ok <- validate_approval_record(fields),
         {:ok, audit_fields} <- approval_audit_fields(actor) do
      Repository.create(settings, :approval_records, Map.merge(scoped_fields, audit_fields))
    end
  end

  def create(settings, actor, resource, fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    with :ok <- authorize(actor, :create, trusted_target),
         {:ok, scoped_fields} <- stamp_trusted_scope(fields, trusted_target) do
      Repository.create(settings, resource, scoped_fields)
    end
  end

  @spec update_existing(map(), map(), atom(), String.t(), map(), String.t() | nil) ::
          :ok | {:error, term()}
  def update_existing(_settings, _actor, :approval_records, _item_id, _fields, _etag),
    do: {:error, :approval_records_are_immutable}

  def update_existing(settings, actor, resource, item_id, fields, etag)
      when is_binary(item_id) and is_map(fields) do
    with {:ok, item} <- Repository.get(settings, resource, item_id),
         {:ok, trusted_scope} <- scope_from_item(item),
         :ok <- authorize(actor, :update, trusted_scope),
         :ok <- reject_scope_changes(fields) do
      Repository.update(settings, resource, item_id, fields, etag)
    end
  end

  # Deliberately do not expose an update function that accepts a caller-supplied
  # scope. Use update_existing/6, which retrieves the record from SharePoint
  # before checking authorization.
  @spec list(map(), map(), atom(), keyword(), map()) ::
          {:ok, [map()]} | {:error, term()}
  def list(settings, actor, resource, opts, trusted_scope) when is_map(trusted_scope) do
    with :ok <- authorize(actor, :read, trusted_scope) do
      Repository.list(settings, resource, opts)
    end
  end

  defp validate_approval_record(fields) do
    decision = get_field(fields, ["Decision", "decision"])
    parent_record_id = get_field(fields, ["ParentRecordId", "parent_record_id"])
    approved_amount = get_field(fields, ["ApprovedAmount", "approved_amount"])

    cond do
      decision not in ["Approved", "Rejected"] ->
        {:error, :invalid_approval_decision}

      not (is_binary(parent_record_id) and String.trim(parent_record_id) != "") ->
        {:error, :parent_record_id_required}

      not (is_number(approved_amount) and approved_amount >= 0) ->
        {:error, :invalid_approved_amount}

      true ->
        :ok
    end
  end

  # Audit identity and timestamp are always generated from the authenticated
  # server actor; caller-supplied values cannot impersonate another approver.
  defp approval_audit_fields(%{role: role} = actor) when is_atom(role) do
    actor_id =
      [Map.get(actor, :id), Map.get(actor, :email)]
      |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))

    if is_binary(actor_id) do
      {:ok,
       %{
         "DecisionBy" => actor_id,
         "DecisionByRole" => Atom.to_string(role),
         "DecisionAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    else
      {:error, :approval_actor_identity_required}
    end
  end

  defp approval_audit_fields(_actor), do: {:error, :approval_actor_identity_required}

  defp approval_action(fields) do
    approval_type = get_field(fields, ["ApprovalType", "approval_type"])

    case approval_type do
      "Repair" -> {:ok, :approve_repair}
      "Additional Repair Cost" -> {:ok, :approve_additional_repair}
      "Towing Invoice" -> {:ok, :approve_towing_invoice}
      _ -> {:error, :invalid_approval_type}
    end
  end

  defp scope_from_item(%{"fields" => fields}) when is_map(fields) do
    project_id = get_field(fields, ["ProjectId", "project_id"])
    city_id = get_field(fields, ["CityId", "city_id"])
    vehicle_id = get_field(fields, ["VehicleId", "vehicle_id"])

    scope = %{
      project_id: normalize_id(project_id),
      city_id: normalize_id(city_id),
      vehicle_id: normalize_id(vehicle_id)
    }

    if Enum.any?(Map.values(scope), &is_binary/1) do
      {:ok, scope}
    else
      {:error, :record_scope_missing}
    end
  end

  defp scope_from_item(_item), do: {:error, :invalid_sharepoint_record}

  defp get_field(fields, names) do
    Enum.find_value(names, fn name -> Map.get(fields, name) end)
  end

  defp normalize_id(value) when is_binary(value) and value != "", do: value
  defp normalize_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_id(_value), do: nil

  @doc false
  def stamp_trusted_scope(fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    mappings = [
      {"ProjectId", :project_id, "project_id"},
      {"CityId", :city_id, "city_id"},
      {"VehicleId", :vehicle_id, "vehicle_id"}
    ]

    Enum.reduce_while(mappings, {:ok, fields}, fn {sharepoint_field, target_key, alias_key}, {:ok, acc} ->
      submitted =
        [Map.get(acc, sharepoint_field), Map.get(acc, alias_key)]
        |> Enum.reject(&is_nil/1)

      trusted_value = Map.get(trusted_target, target_key)

      cond do
        is_nil(trusted_value) and submitted != [] ->
          {:halt, {:error, :submitted_scope_does_not_match_trusted_scope}}

        is_nil(trusted_value) ->
          {:cont, {:ok, Map.delete(acc, alias_key)}}

        Enum.any?(submitted, &(&1 != trusted_value)) ->
          {:halt, {:error, :submitted_scope_does_not_match_trusted_scope}}

        true ->
          scoped =
            acc
            |> Map.delete(target_key)
            |> Map.put(sharepoint_field, trusted_value)

          {:cont, {:ok, scoped}}
      end
    end)
  end

  def stamp_trusted_scope(_fields, _trusted_target),
    do: {:error, :invalid_trusted_scope}

  defp reject_scope_changes(fields) do
    changed_scope_field? =
      Enum.any?(Map.keys(fields), fn key ->
        key
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z_]/, "")
        |> then(&(&1 in @scope_field_names))
      end)

    if changed_scope_field?, do: {:error, :scope_change_requires_reassignment}, else: :ok
  end
end
