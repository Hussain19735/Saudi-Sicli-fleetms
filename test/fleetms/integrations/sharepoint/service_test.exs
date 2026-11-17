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
    actor = %{role: :maintenance_manager, email: "manager@example.com", project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :sharepoint_adapter_not_selected} =
             Service.create(
               %{},
               actor,
               :approval_records,
               %{
                 "ApprovalType" => "Additional Repair Cost",
                 "Decision" => "Approved",
                 "ParentRecordId" => "WO-1",
                 "ApprovedAmount" => 100
               },
               %{project_id: "P-1", city_id: "JED"}
             )

    assert {:error, :forbidden} =
             Service.create(
               %{},
               actor,
               :approval_records,
               %{
                 "ApprovalType" => "Additional Repair Cost",
                 "Decision" => "Approved",
                 "ParentRecordId" => "WO-1",
                 "ApprovedAmount" => 100
               },
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

  test "approval records require a valid decision and parent record" do
    actor = %{role: :maintenance_manager, email: "manager@example.com", project_ids: ["P-1"], city_ids: ["JED"]}
    target = %{project_id: "P-1", city_id: "JED"}

    assert {:error, :invalid_approval_decision} =
             Service.create(%{}, actor, :approval_records, %{
               "ApprovalType" => "Repair",
               "Decision" => "Pending",
               "ParentRecordId" => "WO-1",
               "ApprovedAmount" => 100
             }, target)

    assert {:error, :parent_record_id_required} =
             Service.create(%{}, actor, :approval_records, %{
               "ApprovalType" => "Repair",
               "Decision" => "Approved",
               "ApprovedAmount" => 100
             }, target)
  end

  test "approval records reject negative or missing approved amounts" do
    actor = %{role: :maintenance_manager, email: "manager@example.com", project_ids: ["P-1"], city_ids: ["JED"]}
    target = %{project_id: "P-1", city_id: "JED"}
    fields = %{"ApprovalType" => "Repair", "Decision" => "Approved", "ParentRecordId" => "WO-1"}

    assert {:error, :invalid_approved_amount} =
             Service.create(%{}, actor, :approval_records, Map.put(fields, "ApprovedAmount", -1), target)

    assert {:error, :invalid_approved_amount} =
             Service.create(%{}, actor, :approval_records, fields, target)
  end

  test "approval record requires authenticated approver identity" do
    actor = %{role: :maintenance_manager, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :approval_actor_identity_required} =
             Service.create(%{}, actor, :approval_records, %{
               "ApprovalType" => "Repair",
               "Decision" => "Approved",
               "ParentRecordId" => "WO-1",
               "ApprovedAmount" => 100
             }, %{project_id: "P-1", city_id: "JED"})
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

  test "create stamps missing scope fields from trusted server target" do
    assert {:ok, scoped_fields} =
             Service.stamp_trusted_scope(
               %{"Title" => "INV-101"},
               %{project_id: "P-1", city_id: "JED", vehicle_id: "V-1"}
             )

    assert scoped_fields["ProjectId"] == "P-1"
    assert scoped_fields["CityId"] == "JED"
    assert scoped_fields["VehicleId"] == "V-1"
    refute Map.has_key?(scoped_fields, "project_id")
    refute Map.has_key?(scoped_fields, "city_id")
    refute Map.has_key?(scoped_fields, "vehicle_id")
  end

  test "create rejects caller-supplied scope that conflicts with trusted target" do
    assert {:error, :submitted_scope_does_not_match_trusted_scope} =
             Service.stamp_trusted_scope(
               %{"ProjectId" => "P-2"},
               %{project_id: "P-1", city_id: "JED"}
             )
  end

  test "create rejects scope values without a trusted server relationship" do
    assert {:error, :submitted_scope_does_not_match_trusted_scope} =
             Service.stamp_trusted_scope(
               %{"VehicleId" => "V-1"},
               %{project_id: "P-1"}
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
