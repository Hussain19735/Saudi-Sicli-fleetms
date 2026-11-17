defmodule Fleetms.Integrations.SharePoint.ServiceTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.SharePoint.Service

  test "denies create before contacting SharePoint when scope is missing" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{"Title" => "Test"}, %{})
  end

  test "denies create when target project is outside the actor scope" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}
    target = %{project_id: "P-2", city_id: "JED"}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{"Title" => "Test"}, target)
  end

  test "update_existing fails closed when SharePoint is not configured" do
    actor = %{role: :company_admin}

    assert {:error, :sharepoint_adapter_not_selected} =
             Service.update_existing(%{}, actor, :breakdown_reports, "42", %{"Title" => "Changed"}, nil)
  end

  test "legacy update API accepting caller-supplied scope is not exposed" do
    refute function_exported?(Service, :update, 7)
  end

  test "denies list when scope is absent" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :forbidden} =
             Service.list(%{}, actor, :vehicles, [], %{})
  end

  test "create rejects fields that disagree with trusted scope" do
    actor = %{role: :company_admin}
    trusted = %{project_id: "P-1", city_id: "JED"}

    assert {:error, :submitted_scope_does_not_match_trusted_scope} =
             Service.create(
               %{},
               actor,
               :vehicles,
               %{"ProjectId" => "P-2", "CityId" => "JED"},
               trusted
             )
  end

  test "company admin is authorized for an in-scope operation" do
    assert :ok =
             Service.authorize(%{role: :company_admin}, :update, %{
               project_id: "P-1",
               city_id: "JED"
             })
  end

  test "employee cannot use maintenance operations" do
    actor = %{role: :employee, vehicle_ids: ["V-1"]}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{}, %{vehicle_id: "V-1"})
  end

  test "invoice creation is denied outside the maintenance manager project and city scope" do
    actor = %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :forbidden} =
             Service.create(
               %{},
               actor,
               :invoices,
               %{"Title" => "INV-100", "ProjectId" => "P-2", "CityId" => "JED"},
               %{project_id: "P-2", city_id: "JED"}
             )
  end

  test "company admin cannot create repair approval records" do
    actor = %{role: :company_admin}

    assert {:error, :forbidden} =
             Service.create(
               %{},
               actor,
               :approval_records,
               %{"ApprovalType" => "Repair", "Decision" => "Approved"},
               %{project_id: "P-1", city_id: "JED"}
             )
  end

  test "maintenance manager approval record requires assigned project and city scope" do
    actor = %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :sharepoint_adapter_not_selected} =
             Service.create(
               %{},
               actor,
               :approval_records,
               %{"ApprovalType" => "Additional Repair Cost", "Decision" => "Approved"},
               %{project_id: "P-1", city_id: "JED"}
             )

    assert {:error, :forbidden} =
             Service.create(
               %{},
               actor,
               :approval_records,
               %{"ApprovalType" => "Additional Repair Cost", "Decision" => "Approved"},
               %{project_id: "P-2", city_id: "JED"}
             )
  end

  test "approval records cannot be edited after creation" do
    assert {:error, :approval_records_are_immutable} =
             Service.update_existing(
               %{},
               %{role: :company_admin},
               :approval_records,
               "approval-1",
               %{"Decision" => "Rejected"},
               nil
             )
  end

  test "approval record creation rejects unknown approval types" do
    assert {:error, :invalid_approval_type} =
             Service.create(
               %{},
               %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]},
               :approval_records,
               %{"ApprovalType" => "Unknown"},
               %{project_id: "P-1", city_id: "JED"}
             )
  end

  test "invoice creation rejects invoice fields that disagree with trusted scope" do
    actor = %{role: :company_admin}

    assert {:error, :submitted_scope_does_not_match_trusted_scope} =
             Service.create(
               %{},
               actor,
               :invoices,
               %{"Title" => "INV-101", "ProjectId" => "P-2", "CityId" => "JED"},
               %{project_id: "P-1", city_id: "JED"}
             )
  end
end
