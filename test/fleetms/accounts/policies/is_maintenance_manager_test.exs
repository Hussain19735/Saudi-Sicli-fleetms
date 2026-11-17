defmodule Fleetms.Accounts.User.Policies.IsMaintenanceManagerTest do
  use ExUnit.Case, async: true

  alias Fleetms.Accounts.User
  alias Fleetms.Accounts.User.Policies.IsMaintenanceManager

  describe "match?/3" do
    test "returns true for a maintenance manager" do
      user = struct!(User, roles: [:maintenance_manager])

      assert IsMaintenanceManager.match?(user, %{}, [])
    end

    test "returns false for a user without the maintenance manager role" do
      user = struct!(User, roles: [:technician])

      refute IsMaintenanceManager.match?(user, %{}, [])
    end

    test "returns false when the actor is not a user" do
      refute IsMaintenanceManager.match?(nil, %{}, [])
    end
  end
end
