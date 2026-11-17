defmodule Fleetms.Integrations.SharePoint.AccessPolicy do
  @moduledoc """
  Server-side policy rules for fleet SharePoint operations.

  Callers must supply the authenticated actor and the target record's scope
  from trusted server-side data. Never use project/city/vehicle scope supplied
  only by browser parameters.
  """

  @manager_roles [:company_admin, :maintenance_manager]
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
      when role in @manager_roles and action in [
             :read,
             :create,
             :update,
             :approve_repair,
             :approve_additional_repair,
             :approve_towing_invoice,
             :manage_users,
             :manage_settings
           ],
      do: :ok

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

  defp in_scope?(actor, target) do
    project_ok? =
      is_nil(Map.get(target, :project_id)) or
        Map.get(target, :project_id) in Map.get(actor, :project_ids, [])

    city_ok? =
      is_nil(Map.get(target, :city_id)) or
        Map.get(target, :city_id) in Map.get(actor, :city_ids, [])

    project_ok? and city_ok?
  end
end
