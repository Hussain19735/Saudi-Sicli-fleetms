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
  def create(settings, actor, resource, fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    with :ok <- authorize(actor, :create, trusted_target),
         :ok <- validate_create_scope(fields, trusted_target) do
      Repository.create(settings, resource, fields)
    end
  end

  @spec update(map(), term(), atom(), String.t(), map(), String.t() | nil, map()) ::
          :ok | {:error, term()}
  def update(settings, actor, resource, item_id, fields, etag, trusted_existing_target)
      when is_map(fields) and is_map(trusted_existing_target) do
    with :ok <- authorize(actor, :update, trusted_existing_target),
         :ok <- reject_scope_changes(fields) do
      Repository.update(settings, resource, item_id, fields, etag)
    end
  end

  @spec list(map(), map(), atom(), keyword(), map()) ::
          {:ok, [map()]} | {:error, term()}
  def list(settings, actor, resource, opts, trusted_scope) when is_map(trusted_scope) do
    with :ok <- authorize(actor, :read, trusted_scope) do
      Repository.list(settings, resource, opts)
    end
  end

  defp validate_create_scope(fields, trusted_target) do
    mappings = [
      {"ProjectId", :project_id},
      {"project_id", :project_id},
      {"CityId", :city_id},
      {"city_id", :city_id},
      {"VehicleId", :vehicle_id},
      {"vehicle_id", :vehicle_id}
    ]

    mismatch? =
      Enum.any?(mappings, fn {field, scope_key} ->
        case Map.fetch(fields, field) do
          {:ok, value} -> value != Map.get(trusted_target, scope_key)
          :error -> false
        end
      end)

    if mismatch?, do: {:error, :submitted_scope_does_not_match_trusted_scope}, else: :ok
  end

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
