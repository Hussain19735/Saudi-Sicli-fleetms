defmodule Fleetms.Accounts.User.Policies.IsMaintenanceManager do
  @moduledoc """
  Checks if the actor/user has a `maintenance_manager` role.
  """
  use Ash.Policy.SimpleCheck

  alias Fleetms.Accounts.User

  @impl true
  def describe(_opts), do: "Check if actor has a `maintenance_manager` role"

  @impl true
  def match?(%User{roles: roles}, _context, _opts) do
    :maintenance_manager in roles
  end

  @impl true
  def match?(_actor, _context, _opts), do: false
end
