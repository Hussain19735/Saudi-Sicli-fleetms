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
end
