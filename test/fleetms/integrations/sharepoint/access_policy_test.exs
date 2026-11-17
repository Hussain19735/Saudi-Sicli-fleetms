defmodule Fleetms.Integrations.SharePoint.AccessPolicyTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.SharePoint.AccessPolicy

  test "company admin can manage users but cannot approve repair or towing work" do
    actor = %{role: :company_admin}
    assert :ok = AccessPolicy.authorize(actor, :manage_users, %{})
    assert :ok = AccessPolicy.authorize(actor, :manage_settings, %{})
    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :approve_repair, %{project_id: "P-1"})
    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :approve_additional_repair, %{project_id: "P-1"})
    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :approve_towing_invoice, %{project_id: "P-1"})
  end

  test "maintenance manager has approval authority only within assigned scope" do
    actor = %{role: :maintenance_manager, project_ids: ["P-100"], city_ids: ["JED"]}
    target = %{project_id: "P-100", city_id: "JED"}

    assert :ok = AccessPolicy.authorize(actor, :approve_towing_invoice, target)
    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_towing_invoice, %{project_id: "P-200", city_id: "JED"})
  end

  test "maintenance manager can approve only within assigned scope and cannot manage users" do
    actor = %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]}
    target = %{project_id: "P-1", city_id: "JED"}

    assert :ok = AccessPolicy.authorize(actor, :approve_repair, target)
    assert :ok = AccessPolicy.authorize(actor, :approve_towing_invoice, target)
    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_repair, %{project_id: "P-2", city_id: "JED"})
    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :manage_users, target)
    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :manage_settings, target)
  end

  test "maintenance manager can approve additional repair costs only in scope" do
    actor = %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]}
    assert :ok = AccessPolicy.authorize(actor, :approve_additional_repair, %{project_id: "P-1", city_id: "JED"})
    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_additional_repair, %{project_id: "P-2", city_id: "JED"})
  end

  test "maintenance team can approve only within assigned project and city" do
    actor = %{
      role: :maintenance_team,
      project_ids: ["P-100"],
      city_ids: ["JED"]
    }

    assert :ok =
             AccessPolicy.authorize(actor, :approve_repair, %{
               project_id: "P-100",
               city_id: "JED"
             })

    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_repair, %{
               project_id: "P-200",
               city_id: "JED"
             })
  end

  test "employee can read and report only an assigned vehicle" do
    actor = %{role: :employee, vehicle_ids: ["V-1"]}

    assert :ok = AccessPolicy.authorize(actor, :read, %{vehicle_id: "V-1"})
    assert :ok = AccessPolicy.authorize(actor, :create_breakdown, %{vehicle_id: "V-1"})
    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :read, %{vehicle_id: "V-2"})
    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_repair, %{vehicle_id: "V-1"})
  end

  test "legacy admin role maps to company admin permissions" do
    assert :ok = AccessPolicy.authorize(%{role: :admin}, :manage_users, %{})
  end

  test "legacy technician role uses maintenance-team project scope" do
    actor = %{role: :technician, project_ids: ["P-1"]}

    assert :ok =
             AccessPolicy.authorize(actor, :approve_repair, %{project_id: "P-1"})

    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :approve_repair, %{project_id: "P-2"})
  end

  test "maintenance team is denied when record scope is missing" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"]}

    assert {:error, :forbidden} = AccessPolicy.authorize(actor, :read, %{})
  end

  test "legacy driver role is limited to assigned vehicle operations" do
    actor = %{role: :driver, vehicle_ids: ["V-1"]}

    assert :ok =
             AccessPolicy.authorize(actor, :create_breakdown, %{vehicle_id: "V-1"})

    assert {:error, :forbidden} =
             AccessPolicy.authorize(actor, :create_breakdown, %{vehicle_id: "V-2"})
  end

  test "unknown roles and actions are denied by default" do
    assert {:error, :forbidden} =
             AccessPolicy.authorize(%{role: :unknown}, :read, %{})
  end
end
