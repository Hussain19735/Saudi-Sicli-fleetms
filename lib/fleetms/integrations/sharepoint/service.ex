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

  def create(settings, actor, :invoices, fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    with :ok <- authorize(actor, :create, trusted_target),
         {:ok, scoped_fields} <- stamp_trusted_scope(fields, trusted_target),
         {:ok, invoice_fields} <- prepare_invoice_financial_fields(scoped_fields),
         :ok <- validate_invoice_approval(settings, invoice_fields, trusted_target) do
      Repository.create(settings, :invoices, invoice_fields)
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
         :ok <- reject_scope_changes(fields),
         :ok <- maybe_reject_invoice_financial_changes(resource, fields) do
      Repository.update(settings, resource, item_id, fields, etag)
    end
  end

  @doc """
  Records a single full invoice payment. Partial payments are intentionally not
  supported by the current SharePoint invoice contract. The record ETag is
  required so concurrent payment attempts cannot silently overwrite each other.
  """
  def record_invoice_payment(settings, actor, invoice_id, payment_reference)
      when is_binary(invoice_id) and is_binary(payment_reference) do
    if String.trim(payment_reference) == "" do
      {:error, :payment_reference_required}
    else
      with {:ok, invoice} <- Repository.get(settings, :invoices, invoice_id),
           {:ok, trusted_scope} <- scope_from_item(invoice),
           :ok <- authorize(actor, :record_payment, trusted_scope),
           {:ok, invoice_fields} <- work_order_fields(invoice),
           {:ok, update_fields} <- build_full_payment_update(invoice_fields, actor, payment_reference),
           etag when is_binary(etag) and etag != "" <-
             Map.get(invoice, "eTag") || Map.get(invoice, "@odata.etag"),
           :ok <- Repository.update(settings, :invoices, invoice_id, update_fields, etag) do
        :ok
      else
        nil -> {:error, :invoice_etag_required}
        {:error, _} = error -> error
        _ -> {:error, :invoice_etag_required}
      end
    end
  end

  def record_invoice_payment(_settings, _actor, _invoice_id, _payment_reference),
    do: {:error, :payment_reference_required}

  @doc false
  def prepare_invoice_financial_fields(fields) when is_map(fields) do
    with {:ok, amount} <- decimal_amount(get_field(fields, ["Amount", "amount"])),
         {:ok, vat} <- decimal_amount(get_field(fields, ["VATAmount", "vat_amount"])),
         {:ok, total} <- decimal_amount(get_field(fields, ["TotalAmount", "total_amount"])),
         true <- Enum.all?([amount, vat, total], &(Decimal.compare(&1, Decimal.new(0)) in [:gt, :eq])),
         true <- Decimal.compare(total, Decimal.new(0)) == :gt,
         true <- Enum.all?([amount, vat, total], &(Decimal.compare(Decimal.round(&1, 2), &1) == :eq)),
         true <- Decimal.compare(Decimal.add(amount, vat), total) == :eq do
      {:ok,
       fields
       |> Map.delete("paid_amount")
       |> Map.delete("remaining_amount")
       |> Map.delete("payment_status")
       |> Map.delete("payment_reference")
       |> Map.delete("paid_at")
       |> Map.delete("paid_by")
       |> Map.delete("paid_by_role")
       |> Map.put("PaidAmount", 0.0)
       |> Map.put("RemainingAmount", Decimal.to_float(total))
       |> Map.put("PaymentStatus", "Unpaid")
       |> Map.delete("PaymentReference")
       |> Map.delete("PaidAt")
       |> Map.delete("PaidBy")
       |> Map.delete("PaidByRole")}
    else
      false -> {:error, :invoice_total_mismatch_or_negative_amount}
      :error -> {:error, :invoice_amounts_missing_or_invalid}
    end
  end

  def prepare_invoice_financial_fields(_fields),
    do: {:error, :invoice_amounts_missing_or_invalid}

  @doc false
  def build_full_payment_update(fields, actor, payment_reference, paid_at \\ DateTime.utc_now())
      when is_map(fields) and is_map(actor) and is_binary(payment_reference) do
    with true <- String.trim(payment_reference) != "",
         {:ok, total} <- decimal_amount(get_field(fields, ["TotalAmount", "total_amount"])),
         {:ok, paid} <- decimal_amount(get_field(fields, ["PaidAmount", "paid_amount"]) || 0),
         true <- Decimal.compare(total, Decimal.new(0)) == :gt,
         true <- Decimal.compare(paid, Decimal.new(0)) == :eq,
         true <- get_field(fields, ["PaymentStatus", "payment_status"]) != "Paid",
         actor_id when is_binary(actor_id) and actor_id != "" <-
           [Map.get(actor, :id), Map.get(actor, :email)] |> Enum.find(&(is_binary(&1) and String.trim(&1) != "")),
         role when is_atom(role) <- Map.get(actor, :role) do
      {:ok,
       %{
         "PaidAmount" => Decimal.to_float(Decimal.round(total, 2)),
         "RemainingAmount" => 0.0,
         "PaymentStatus" => "Paid",
         "PaymentReference" => String.trim(payment_reference),
         "PaidAt" => DateTime.truncate(paid_at, :second) |> DateTime.to_iso8601(),
         "PaidBy" => actor_id,
         "PaidByRole" => Atom.to_string(role)
       }}
    else
      false -> {:error, :invoice_already_paid_or_payment_reference_required}
      nil -> {:error, :invoice_payment_actor_identity_required}
      :error -> {:error, :invoice_amounts_missing_or_invalid}
      _ -> {:error, :invoice_payment_actor_identity_required}
    end
  end

  def build_full_payment_update(_fields, _actor, _payment_reference, _paid_at),
    do: {:error, :invoice_amounts_missing_or_invalid}

  defp maybe_reject_invoice_financial_changes(:invoices, fields),
    do: reject_invoice_financial_changes(fields)

  defp maybe_reject_invoice_financial_changes(_resource, _fields), do: :ok

  defp reject_invoice_financial_changes(fields) do
    protected = ~w(amount vatamount totalamount paidamount remainingamount paymentstatus paymentreference paidat paidby paidbyrole approvalstatus)

    changed? =
      Enum.any?(Map.keys(fields), fn key ->
        key
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z]/, "")
        |> then(&(&1 in protected))
      end)

    if changed?, do: {:error, :invoice_financial_update_requires_payment_operation}, else: :ok
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

  defp validate_invoice_approval(settings, fields, trusted_target) do
    case get_field(fields, ["InvoiceType", "invoice_type"]) do
      "Repair" ->
        validate_repair_invoice_approval(settings, fields, trusted_target)

      "Towing" ->
        validate_towing_invoice_approval(settings, fields, trusted_target)

      type when type in ["Spare Parts", "Periodic Inspection", "Tires", "Other"] ->
        :ok

      _ ->
        {:error, :invalid_invoice_type}
    end
  end

  defp validate_repair_invoice_approval(settings, fields, trusted_target) do
    case get_field(fields, ["WorkOrderId", "work_order_id"]) do
      work_order_id when is_binary(work_order_id) and work_order_id != "" ->
        with {:ok, work_order} <- Repository.get(settings, :work_orders, work_order_id),
             {:ok, work_order_fields} <- work_order_fields(work_order),
             {:ok, work_order_scope} <- scope_from_item(work_order),
             :ok <- ensure_scope_match(work_order_scope, trusted_target),
             {:ok, additional_approved} <-
               approved_additional_amount(settings, work_order_id, work_order_scope) do
          validate_repair_cost_approval(
            get_field(work_order_fields, ["ActualRepairCost", "actual_repair_cost"]),
            get_field(work_order_fields, ["ApprovedRepairCost", "approved_repair_cost"]),
            additional_approved
          )
        end

      _ ->
        {:error, :work_order_id_required}
    end
  end

  defp validate_towing_invoice_approval(settings, fields, trusted_target) do
    case get_field(fields, ["BreakdownReportId", "breakdown_report_id"]) do
      report_id when is_binary(report_id) and report_id != "" ->
        with {:ok, report} <- Repository.get(settings, :breakdown_reports, report_id),
             {:ok, report_scope} <- scope_from_item(report),
             :ok <- ensure_scope_match(report_scope, trusted_target),
             {:ok, approved_amount} <- approved_towing_amount(settings, report_id, report_scope) do
          validate_towing_invoice_amount(
            get_field(fields, ["TotalAmount", "total_amount"]),
            approved_amount
          )
        end

      _ ->
        {:error, :breakdown_report_id_required}
    end
  end

  defp approved_towing_amount(settings, report_id, report_scope) do
    with {:ok, records} <- Repository.list(settings, :approval_records, []) do
      result =
        Enum.reduce_while(records, {:ok, nil}, fn record, {:ok, highest} ->
          if approved_towing_invoice_for?(record, report_id, report_scope) do
            amount =
              record
              |> Map.get("fields", %{})
              |> get_field(["ApprovedAmount", "approved_amount"])

            case decimal_amount(amount) do
              {:ok, decimal} ->
                highest =
                  if is_nil(highest) or Decimal.compare(decimal, highest) == :gt,
                    do: decimal,
                    else: highest

                {:cont, {:ok, highest}}

              :error ->
                {:halt, {:error, :invalid_towing_approval_amount}}
            end
          else
            {:cont, {:ok, highest}}
          end
        end)

      case result do
        {:ok, nil} -> {:error, :towing_invoice_approval_required}
        other -> other
      end
    end
  end

  defp approved_towing_invoice_for?(%{"fields" => fields}, report_id, report_scope)
       when is_map(fields) do
    get_field(fields, ["ParentRecordId", "parent_record_id"]) == report_id and
      get_field(fields, ["ApprovalType", "approval_type"]) == "Towing Invoice" and
      get_field(fields, ["Decision", "decision"]) == "Approved" and
      Enum.all?([:project_id, :city_id, :vehicle_id], fn key ->
        case Map.get(report_scope, key) do
          nil -> true
          value -> get_field(fields, [scope_field_name(key)]) == value
        end
      end)
  end

  defp approved_towing_invoice_for?(_record, _report_id, _report_scope), do: false

  @doc false
  def validate_towing_invoice_amount(invoice_total, approved_amount) do
    with {:ok, invoice} <- decimal_amount(invoice_total),
         {:ok, approved} <- decimal_amount(approved_amount),
         true <- Decimal.compare(invoice, approved) in [:lt, :eq] do
      :ok
    else
      false -> {:error, :towing_invoice_exceeds_approved_amount}
      :error -> {:error, :towing_invoice_amount_missing_or_invalid}
    end
  end

  defp work_order_fields(%{"fields" => fields}) when is_map(fields), do: {:ok, fields}
  defp work_order_fields(_work_order), do: {:error, :invalid_work_order_record}

  defp ensure_scope_match(record_scope, trusted_target) do
    matches? =
      Enum.all?([:project_id, :city_id, :vehicle_id], fn key ->
        case Map.get(trusted_target, key) do
          nil -> true
          trusted_value -> Map.get(record_scope, key) == trusted_value
        end
      end)

    if matches?, do: :ok, else: {:error, :work_order_scope_mismatch}
  end

  defp approved_additional_amount(settings, work_order_id, work_order_scope) do
    with {:ok, records} <- Repository.list(settings, :approval_records, []) do
      records
      |> Enum.filter(&approved_additional_repair_for?(&1, work_order_id, work_order_scope))
      |> Enum.reduce_while({:ok, Decimal.new(0)}, fn record, {:ok, total} ->
        amount =
          record
          |> Map.get("fields", %{})
          |> get_field(["ApprovedAmount", "approved_amount"])

        case decimal_amount(amount) do
          {:ok, decimal} -> {:cont, {:ok, Decimal.add(total, decimal)}}
          :error -> {:halt, {:error, :invalid_additional_approval_amount}}
        end
      end)
    end
  end

  defp approved_additional_repair_for?(%{"fields" => fields}, work_order_id, work_order_scope)
       when is_map(fields) do
    get_field(fields, ["ParentRecordId", "parent_record_id"]) == work_order_id and
      get_field(fields, ["ApprovalType", "approval_type"]) == "Additional Repair Cost" and
      get_field(fields, ["Decision", "decision"]) == "Approved" and
      Enum.all?([:project_id, :city_id, :vehicle_id], fn key ->
        case Map.get(work_order_scope, key) do
          nil -> true
          value -> get_field(fields, [scope_field_name(key)]) == value
        end
      end)
  end

  defp approved_additional_repair_for?(_record, _work_order_id, _work_order_scope), do: false

  defp scope_field_name(:project_id), do: "ProjectId"
  defp scope_field_name(:city_id), do: "CityId"
  defp scope_field_name(:vehicle_id), do: "VehicleId"

  @doc false
  def validate_repair_cost_approval(actual_cost, approved_cost, additional_approved) do
    with {:ok, actual} <- decimal_amount(actual_cost),
         {:ok, approved} <- decimal_amount(approved_cost),
         {:ok, additional} <- decimal_amount(additional_approved),
         true <- Decimal.compare(actual, Decimal.add(approved, additional)) in [:lt, :eq] do
      :ok
    else
      false -> {:error, :additional_repair_approval_required}
      :error -> {:error, :repair_cost_data_missing_or_invalid}
    end
  end

  defp decimal_amount(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp decimal_amount(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  defp decimal_amount(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> :error
    end
  end

  defp decimal_amount(_value), do: :error

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
            |> Map.delete(alias_key)
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
