defmodule Fleetms.Integrations.WhatsApp.VehicleExpiryReminderTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.WhatsApp.VehicleExpiryReminder

  test "returns reminders on 30-day and 15-day milestones only" do
    today = ~D[2026-11-17]

    vehicle = %{
      registration_expiry_date: ~D[2026-12-17],
      insurance_expiry_date: ~D[2026-12-02],
      periodic_inspection_expiry_date: ~D[2026-12-20]
    }

    assert [
             %{document_type: :registration, days_before: 30},
             %{document_type: :insurance, days_before: 15}
           ] = VehicleExpiryReminder.due_documents(vehicle, today)
  end

  test "ignores missing dates and dates outside reminder milestones" do
    vehicle = %{
      registration_expiry_date: nil,
      insurance_expiry_date: ~D[2026-11-18],
      periodic_inspection_expiry_date: ~D[2027-01-01]
    }

    assert [] = VehicleExpiryReminder.due_documents(vehicle, ~D[2026-11-17])
  end

  test "normalizes common Saudi mobile numbers and E.164 numbers" do
    assert {:ok, "+966501234567"} = VehicleExpiryReminder.normalize_phone("0501234567")
    assert {:ok, "+966501234567"} = VehicleExpiryReminder.normalize_phone("966501234567")
    assert {:ok, "+966501234567"} = VehicleExpiryReminder.normalize_phone("+966501234567")
    assert {:ok, "+14155552671"} = VehicleExpiryReminder.normalize_phone("+14155552671")
    assert {:error, :invalid_phone} = VehicleExpiryReminder.normalize_phone("12345")
  end
  test "builds five body parameters for the approved template" do
    vehicle = %{name: "Fleet 12", license_plate: "ABC 1234"}

    reminder = %{
      expiry_date: ~D[2026-12-17],
      days_before: 30,
      arabic_label: "انتهاء استمارة المركبة",
      english_label: "Vehicle registration"
    }

    assert [
             %{
               type: "body",
               parameters: [
                 %{type: "text", text: "Fleet 12 - ABC 1234"},
                 %{type: "text", text: "انتهاء استمارة المركبة"},
                 %{type: "text", text: "2026-12-17"},
                 %{type: "text", text: "30"},
                 %{type: "text", text: "يرجى التجديد قبل تاريخ الانتهاء"}
               ]
             }
           ] = VehicleExpiryReminder.template_components(vehicle, reminder, "ar")
  end

end
