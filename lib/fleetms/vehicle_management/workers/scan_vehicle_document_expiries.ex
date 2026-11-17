defmodule Fleetms.VehicleManagement.Workers.ScanVehicleDocumentExpiries do
  @moduledoc """
  Daily scan for active vehicle assignments with registration, insurance, or
  periodic-inspection documents reaching the 30-day or 15-day reminder date.
  """

  use Oban.Worker, queue: :whatsapp_notifications, max_attempts: 3

  alias Fleetms.Accounts
  alias Fleetms.Accounts.Organization
  alias Fleetms.Integrations.WhatsApp.VehicleExpiryReminder
  alias Fleetms.VehicleManagement.VehicleAssignment
  alias Fleetms.VehicleManagement.Workers.SendVehicleDocumentExpiryReminder

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    settings = Application.get_env(:fleetms, :whatsapp, %{})

    if Map.get(settings, :vehicle_expiry_notifications_enabled, false) do
      today = DateTime.add(DateTime.utc_now(), 3 * 60 * 60, :second) |> DateTime.to_date()
      now = DateTime.utc_now()

      Accounts.get_all_tenants!()
      |> Enum.each(fn tenant ->
        tenant_prefix = Organization.get_schema_prefix() <> tenant.id

        VehicleAssignment
        |> Ash.Query.filter(start_datetime <= ^now and (is_nil(end_datetime) or end_datetime > ^now))
        |> Ash.Query.load(assignee: [:user_profile], vehicle: [])
        |> Ash.read!(tenant: tenant)
        |> Enum.each(fn assignment ->
          enqueue_due_reminders(assignment, tenant_prefix, today)
        end)
      end)
    end

    :ok
  end

  defp enqueue_due_reminders(%{vehicle: nil}, _tenant, _today), do: :ok
  defp enqueue_due_reminders(%{assignee: nil}, _tenant, _today), do: :ok

  defp enqueue_due_reminders(assignment, tenant, today) do
    phone =
      get_in(assignment, [:assignee, :user_profile, :phone_number])

    case VehicleExpiryReminder.normalize_phone(phone) do
      {:ok, _normalized_phone} ->
        assignment.vehicle
        |> VehicleExpiryReminder.due_documents(today)
        |> Enum.each(fn reminder ->
          args = %{
            "tenant" => tenant,
            "vehicle_id" => assignment.vehicle.id,
            "assignment_id" => assignment.id,
            "document_type" => Atom.to_string(reminder.document_type),
            "expiry_date" => Date.to_iso8601(reminder.expiry_date),
            "days_before" => reminder.days_before
          }

          case Oban.insert(SendVehicleDocumentExpiryReminder.new(args)) do
            {:ok, _job} -> :ok
            {:error, reason} -> Logger.error("Could not enqueue vehicle document reminder: #{inspect(reason)}")
          end
        end)

      {:error, :invalid_phone} ->
        :ok
    end
  end
end
