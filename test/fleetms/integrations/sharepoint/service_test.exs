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

  test "towing invoice requires a linked breakdown report" do
    assert {:error, :breakdown_report_id_required} =
             Service.create(
               %{},
               %{role: :company_admin},
               :invoices,
               %{"InvoiceType" => "Towing", "Amount" => 250, "VATAmount" => 0, "TotalAmount" => 250},
               %{project_id: "P-1", city_id: "JED"}
             )
  end

  test "towing invoice cannot exceed its approved amount" do
    assert :ok = Service.validate_towing_invoice_amount(250, 250)
    assert :ok = Service.validate_towing_invoice_amount(200, 250)

    assert {:error, :towing_invoice_exceeds_approved_amount} =
             Service.validate_towing_invoice_amount(250.01, 250)
  end

  test "towing invoice fails closed when its amount or approval is invalid" do
    assert {:error, :towing_invoice_amount_missing_or_invalid} =
             Service.validate_towing_invoice_amount(nil, 250)

    assert {:error, :towing_invoice_amount_missing_or_invalid} =
             Service.validate_towing_invoice_amount(250, "invalid")
  end

  test "repair invoice requires a linked work order" do
    assert {:error, :work_order_id_required} =
             Service.create(
               %{},
               %{role: :company_admin},
               :invoices,
               %{"InvoiceType" => "Repair", "Amount" => 100, "VATAmount" => 15, "TotalAmount" => 115},
               %{project_id: "P-1", city_id: "JED"}
             )
  end

  test "repair invoice is allowed when actual cost is within original and additional approvals" do
    assert :ok = Service.validate_repair_cost_approval(1_500, 1_000, 500)
    assert :ok = Service.validate_repair_cost_approval(900, 1_000, 0)
  end

  test "repair invoice is blocked when additional approval does not cover the overrun" do
    assert {:error, :additional_repair_approval_required} =
             Service.validate_repair_cost_approval(1_501, 1_000, 500)
  end

  test "repair invoice fails closed when approved cost data is missing or invalid" do
    assert {:error, :repair_cost_data_missing_or_invalid} =
             Service.validate_repair_cost_approval(nil, 1_000, 0)

    assert {:error, :repair_cost_data_missing_or_invalid} =
             Service.validate_repair_cost_approval(1_500, "not-a-number", 500)
  end

  test "invoice creation calculates unpaid and remaining amounts on the server" do
    assert {:ok, fields} =
             Service.prepare_invoice_financial_fields(%{
               "Amount" => 100,
               "VATAmount" => 15,
               "TotalAmount" => 115,
               "PaidAmount" => 115,
               "RemainingAmount" => 0,
               "PaymentStatus" => "Paid",
               "PaymentReference" => "UNTRUSTED",
               "ApprovalStatus" => "Paid",
               "ApprovedBy" => "UNTRUSTED",
               "SentToFinanceBy" => "UNTRUSTED"
             })

    assert fields["Amount"] == 100.0
    assert fields["VATAmount"] == 15.0
    assert fields["TotalAmount"] == 115.0
    assert fields["PaidAmount"] == 0.0
    assert fields["RemainingAmount"] == 115.0
    assert fields["PaymentStatus"] == "Unpaid"
    assert fields["ApprovalStatus"] == "Received"
    refute Map.has_key?(fields, "PaymentReference")
    refute Map.has_key?(fields, "ApprovedBy")
    refute Map.has_key?(fields, "SentToFinanceBy")
  end

  test "invoice creation rejects inconsistent or negative totals" do
    assert {:error, :invoice_total_mismatch_or_negative_amount} =
             Service.prepare_invoice_financial_fields(%{
               "Amount" => 100,
               "VATAmount" => 15,
               "TotalAmount" => 120
             })

    assert {:error, :invoice_total_mismatch_or_negative_amount} =
             Service.prepare_invoice_financial_fields(%{
               "Amount" => -100,
               "VATAmount" => 0,
               "TotalAmount" => -100
             })
  end

  test "invoice creation requires valid amount, VAT and total values" do
    assert {:error, :invoice_amounts_missing_or_invalid} =
             Service.prepare_invoice_financial_fields(%{
               "Amount" => 100,
               "TotalAmount" => 115
             })
  end

  test "full invoice payment records payer identity and closes the balance" do
    actor = %{role: :finance, id: "finance-1", email: "finance@example.com"}
    paid_at = ~U[2026-11-17 10:00:00Z]

    assert {:ok, update} =
             Service.build_full_payment_update(
               %{"TotalAmount" => 115, "PaidAmount" => 0, "PaymentStatus" => "Unpaid", "ApprovalStatus" => "Sent to Finance"},
               actor,
               "BANK-REF-123",
               paid_at
             )

    assert update["PaidAmount"] == 115.0
    assert update["RemainingAmount"] == 0.0
    assert update["PaymentStatus"] == "Paid"
    assert update["PaymentReference"] == "BANK-REF-123"
    assert update["PaidBy"] == "finance-1"
    assert update["PaidByRole"] == "finance"
    assert update["PaidAt"] == "2026-11-17T10:00:00Z"
  end

  test "invoice cannot be paid twice" do
    assert {:error, :invoice_already_paid_or_payment_reference_required} =
             Service.build_full_payment_update(
               %{"TotalAmount" => 115, "PaidAmount" => 115, "PaymentStatus" => "Paid", "ApprovalStatus" => "Sent to Finance"},
               %{role: :finance, email: "finance@example.com"},
               "BANK-REF-124"
             )
  end

  test "invoice payment requires an authenticated actor identity" do
    assert {:error, :invoice_payment_actor_identity_required} =
             Service.build_full_payment_update(
               %{"TotalAmount" => 115, "PaidAmount" => 0, "ApprovalStatus" => "Sent to Finance"},
               %{role: :finance},
               "BANK-REF-125"
             )
  end

  test "supplier invoice approval and handoff require the correct prior state" do
    manager = %{role: :maintenance_manager, id: "manager-1"}
    at = ~U[2026-11-17 10:00:00Z]

    assert {:ok, approved} =
             Service.build_invoice_status_update(%{"ApprovalStatus" => "Received"}, manager, ["Received", "Under Review"], "Approved", at)

    assert approved["ApprovalStatus"] == "Approved"
    assert approved["ApprovedBy"] == "manager-1"
    assert approved["ApprovedByRole"] == "maintenance_manager"
    assert approved["ApprovedAt"] == "2026-11-17T10:00:00Z"

    assert {:ok, sent} =
             Service.build_invoice_status_update(%{"ApprovalStatus" => "Approved"}, manager, ["Approved"], "Sent to Finance", at)

    assert sent["ApprovalStatus"] == "Sent to Finance"
    assert sent["SentToFinanceBy"] == "manager-1"

    assert {:error, :invalid_invoice_approval_transition} =
             Service.build_invoice_status_update(%{"ApprovalStatus" => "Received"}, manager, ["Approved"], "Sent to Finance", at)

    assert {:error, :invalid_invoice_approval_transition} =
             Service.build_invoice_status_update(%{"ApprovalStatus" => "Rejected"}, manager, ["Received", "Under Review"], "Approved", at)
  end

  test "Finance invoice listing excludes invoices not sent to Finance and out-of-scope invoices" do
    actor = %{role: :finance, project_ids: ["P-1"], city_ids: ["JED"]}
    invoices = [
      %{"fields" => %{"ApprovalStatus" => "Sent to Finance", "ProjectId" => "P-1", "CityId" => "JED"}},
      %{"fields" => %{"ApprovalStatus" => "Approved", "ProjectId" => "P-1", "CityId" => "JED"}},
      %{"fields" => %{"ApprovalStatus" => "Sent to Finance", "ProjectId" => "P-2", "CityId" => "JED"}},
      %{"fields" => %{"ApprovalStatus" => "Sent to Finance", "ProjectId" => "P-1", "CityId" => "RUH"}}
    ]

    assert [visible] = Service.filter_finance_invoice_records(invoices, actor)
    assert visible["fields"]["ProjectId"] == "P-1"
  end

  test "payment cannot be built before the invoice is sent to Finance" do
    assert {:error, :invoice_not_sent_to_finance} =
             Service.build_full_payment_update(
               %{"TotalAmount" => 115, "PaidAmount" => 0, "PaymentStatus" => "Unpaid", "ApprovalStatus" => "Approved"},
               %{role: :finance, email: "finance@example.com"},
               "BANK-REF-127"
             )
  end

  test "generic invoice updates cannot change payment or financial fields" do
    assert {:error, :invoice_financial_update_requires_payment_operation} =
             Service.validate_invoice_generic_update(%{"PaidAmount" => 115})

    assert {:error, :invoice_financial_update_requires_payment_operation} =
             Service.validate_invoice_generic_update(%{"PaymentStatus" => "Paid"})

    assert {:error, :invoice_financial_update_requires_payment_operation} =
             Service.validate_invoice_generic_update(%{"TotalAmount" => 115})

    assert :ok = Service.validate_invoice_generic_update(%{"Notes" => "Invoice reviewed"})
  end

  test "invoice cannot be paid twice even if paid amount is inconsistent" do
    assert {:error, :invoice_already_paid_or_payment_reference_required} =
             Service.build_full_payment_update(
               %{"TotalAmount" => 115, "PaidAmount" => 0, "PaymentStatus" => "Paid", "ApprovalStatus" => "Sent to Finance"},
               %{role: :finance, email: "finance@example.com"},
               "BANK-REF-126"
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
