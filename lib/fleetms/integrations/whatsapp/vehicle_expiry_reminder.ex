defmodule Fleetms.Integrations.WhatsApp.VehicleExpiryReminder do
  @moduledoc """
  Pure rules for vehicle document expiry reminders.
  """

  @documents [
    {:registration, :registration_expiry_date, "انتهاء استمارة المركبة", "Vehicle registration"},
    {:insurance, :insurance_expiry_date, "انتهاء تأمين المركبة", "Vehicle insurance"},
    {:periodic_inspection, :periodic_inspection_expiry_date, "انتهاء الفحص الدوري", "Periodic inspection"}
  ]

  @doc """
  Returns reminders only on the 30-day and 15-day milestones.
  """
  def due_documents(vehicle, %Date{} = today) do
    Enum.flat_map(@documents, fn {document_type, field, arabic_label, english_label} ->
      case Map.get(vehicle, field) do
        %Date{} = expiry_date ->
          days_remaining = Date.diff(expiry_date, today)

          if days_remaining in [30, 15] do
            [
              %{
                document_type: document_type,
                expiry_date: expiry_date,
                days_before: days_remaining,
                arabic_label: arabic_label,
                english_label: english_label
              }
            ]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  @doc """
  Builds the body parameters for the approved five-placeholder template.
  """
  def template_components(vehicle, reminder, language) do
    vehicle_label =
      [Map.get(vehicle, :name), Map.get(vehicle, :license_plate)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" - ")
      |> case do
        "" -> "المركبة"
        value -> value
      end

    document_label =
      if String.starts_with?(language, "ar"),
        do: reminder.arabic_label,
        else: reminder.english_label

    values = [
      vehicle_label,
      document_label,
      Date.to_iso8601(reminder.expiry_date),
      Integer.to_string(reminder.days_before),
      if(String.starts_with?(language, "ar"), do: "يرجى التجديد قبل تاريخ الانتهاء", else: "Please renew before the expiry date")
    ]

    [
      %{
        type: "body",
        parameters: Enum.map(values, &%{type: "text", text: &1})
      }
    ]
  end

  @doc """
  Accepts international E.164 numbers and common Saudi mobile formats.
  """
  def normalize_phone(phone) when is_binary(phone) do
    phone = String.replace(phone, ~r/[\\s\\-()]/, "")

    normalized =
      cond do
        Regex.match?(~r/^05[0-9]{8}$/, phone) -> String.replace_prefix(phone, "0", "+966")
        Regex.match?(~r/^5[0-9]{8}$/, phone) -> "+966" <> phone
        Regex.match?(~r/^9665[0-9]{8}$/, phone) -> "+" <> phone
        Regex.match?(~r/^\+9665[0-9]{8}$/, phone) -> phone
        Regex.match?(~r/^\+[1-9][0-9]{7,14}$/, phone) -> phone
        true -> nil
      end

    if normalized, do: {:ok, normalized}, else: {:error, :invalid_phone}
  end

  def normalize_phone(_), do: {:error, :invalid_phone}
end
