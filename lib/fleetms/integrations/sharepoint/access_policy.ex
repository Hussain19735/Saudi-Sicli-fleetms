defmodule Fleetms.Integrations.SharePoint.AccessPolicy do
  @moduledoc """
  Server-side policy rules for fleet SharePoint operations.

  Callers must supply the authenticated actor and the target record's scope
  from trusted server-side data. Never use project/city/vehicle scope supplied
  only by browser parameters.
  """

  @company_admin_roles [:company_admin]
  @maintenance_manager_roles [:maintenance_manager]
  @maintenance_roles [:maintenance_manager, :maintenance_team]

  @type actor :: %{
          required(:role) => atom(),
          optional(:project_ids) => [String.t()],
          optional(:city_ids) => [String.t()],
          optional(:vehicle_ids) => [String.t()]
        }

  @type target :: %{
          optional(:project_id) => String.t() | nil,
          optional(:city_id) => String.t() | nil,
          optional(:vehicle_id) => String.t() | nil
        }

  @spec authorize(actor(), atom(), target()) :: :ok | {:error, :forbidden}
  def authorize(%{role: role}, action, _target)
      when role in @company_admin_roles and action in [
             :read,
             :create,
             :update,
             :record_payment,
             :manage_users,
             :manage_settings
           ],
      do: :ok

  # Maintenance managers may approve maintenance operations but cannot manage
  # users or global settings. Operational access remains project/city scoped.
  def authorize(%{role: role} = actor, action, target)
      when role in @maintenance_manager_roles and action in [
             :read,
             :create,
             :update,
             :approve_repair,
             :approve_additional_repair,
             :approve_towing_invoice
           ] do
    if in_scope?(actor, target), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%{role: role} = actor, action, target)
      when role in [:admin, :technician, :driver] do
    canonical_role =
      case role do
        :admin -> :company_admin
        :technician -> :maintenance_team
        :driver -> :employee
      end

    authorize(Map.put(actor, :role, canonical_role), action, target)
  end

  def authorize(%{role: role} = actor, action, target)
      when role in @maintenance_roles and action in [
             :read,
             :create,
             :update,
             :approve_repair,
             :approve_additional_repair,
             :approve_towing_invoice
           ] do
    if in_scope?(actor, target), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%{role: :employee} = actor, :read, %{vehicle_id: vehicle_id})
      when is_binary(vehicle_id) do
    if vehicle_id in Map.get(actor, :vehicle_ids, []), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%{role: :employee} = actor, :create_breakdown, %{vehicle_id: vehicle_id})
      when is_binary(vehicle_id) do
    if vehicle_id in Map.get(actor, :vehicle_ids, []), do: :ok, else: {:error, :forbidden}
  end

  def authorize(_actor, _action, _target), do: {:error, :forbidden}

  # Maintenance-team access requires a real project and/or city scope.
  # Every scope dimension present on the record must match the actor's grants.
  # Missing scope is denied rather than treated as unrestricted access.
  defp in_scope?(actor, target) when is_map(target) do
    project_id = Map.get(target, :project_id)
    city_id = Map.get(target, :city_id)

    has_scope? = is_binary(project_id) or is_binary(city_id)

    project_ok? =
      is_nil(project_id) or
        (is_binary(project_id) and project_id in Map.get(actor, :project_ids, []))

    city_ok? =
      is_nil(city_id) or
        (is_binary(city_id) and city_id in Map.get(actor, :city_ids, []))

    has_scope? and project_ok? and city_ok?
  end

  defp in_scope?(_actor, _target), do: false
end
