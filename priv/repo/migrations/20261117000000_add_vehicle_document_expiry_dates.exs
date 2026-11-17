defmodule Fleetms.Repo.Migrations.AddVehicleDocumentExpiryDates do
  use Ecto.Migration

  def change do
    alter table(:vehicles) do
      add :registration_expiry_date, :date
      add :insurance_expiry_date, :date
      add :periodic_inspection_expiry_date, :date
    end
  end
end
