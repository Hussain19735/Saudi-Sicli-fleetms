defmodule Fleetms.VehicleManagement.Workers.SendVehicleDocumentExpiryReminder do
  @moduledoc """
  Sends one approved WhatsApp template for an active vehicle assignment.

  Oban uniqueness prevents the same vehicle/document/milestone from being
  queued repeatedly during the reminder window.
  """

  use Oban.Worker,
    queue: :whatsapp_notifications,
    max_attempts: 1,
    unique: [
      period: 30 * 24 * 60 * 60,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed, :discarded, :cancelled, :failed]
    ]

  alias Fleetms.Integrations.WhatsApp.{Client, VehicleExpiryReminder}
  alias Fleetms.VehicleManagement.VehicleAssignment

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    settings = Application.get_env(:fleetms, :whatsapp, %{})

    if Map.get(settings, :enabled, false) and
         Map.get(settings, :vehicle_expiry_notifications_enabled, false) do
      send_reminder(args, settings)
    else
      :ok
    end
  end

  defp send_reminder(args, settings) do
    with {:ok, expiry_date} <- Date.from_iso8601(args["expiry_date"]),
         {:ok, assignment} <- current_assignment(args),
         {:ok, phone} <- current_phone(assignment),
         {:ok, reminder} <- reminder_data(args, expiry_date),
         template when is_binary(template) <- Map.get(settings, :vehicle_expiry_template),
         language when is_binary(language) <- Map.get(settings, :vehicle_expiry_language, "ar"),
         components <- VehicleExpiryReminder.template_components(assignment.vehicle, reminder, language),
         {:ok, _result} <-
           Client.send_template(settings, phone, template, language, components) do
      :ok
    else
      {:error, :no_current_assignment} ->
        :ok

      {:error, :invalid_phone} ->
        Logger.warning("Vehicle expiry reminder skipped because the assigned driver has no valid WhatsApp number")
        :ok

      {:error, reason} ->
        Logger.error("WhatsApp vehicle expiry reminder failed: #{inspect(reason)}")
        {:error, reason}

      _ ->
        {:error, :invalid_vehicle_expiry_reminder_job}
    end
  end

  defp current_assignment(args) do
    now = DateTime.utc_now()

    query =
      VehicleAssignment
      |> Ash.Query.filter(
        id == ^args["assignment_id"] and vehicle_id == ^args["vehicle_id"] and
          start_datetime <= ^now and (is_nil(end_datetime) or end_datetime > ^now)
      )
      |> Ash.Query.load(assignee: [:user_profile], vehicle: [])

    case Ash.read(query, tenant: args["tenant"]) do
      {:ok, [assignment | _]} when not is_nil(assignment.vehicle) and not is_nil(assignment.assignee) ->
        {:ok, assignment}

      {:ok, _} ->
        {:error, :no_current_assignment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_phone(assignment) do
    assignment
    |> get_in([:assignee, :user_profile, :phone_number])
    |> VehicleExpiryReminder.normalize_phone()
  end

  defp reminder_data(args, expiry_date) do
    document_type =
      case args["document_type"] do
        "registration" -> {:registration, :registration_expiry_date, "انتهاء استمارة المركبة", "Vehicle registration"}
        "insurance" -> {:insurance, :insurance_expiry_date, "انتهاء تأمين المركبة", "Vehicle insurance"}
        "periodic_inspection" -> {:periodic_inspection, :periodic_inspection_expiry_date, "انتهاء الفحص الدوري", "Periodic inspection"}
        _ -> nil
      end

    case document_type do
      {type, field, arabic_label, english_label} ->
        actual_date = Map.get(assignment_vehicle_placeholder(), field)
        _ = actual_date

        {:ok,
         %{
           document_type: type,
           expiry_date: expiry_date,
           days_before: args["days_before"],
           arabic_label: arabic_label,
           english_label: english_label
         }}

      nil ->
        {:error, :invalid_document_type}
    end
  end

  defp assignment_vehicle_placeholder, do: %{}
end
