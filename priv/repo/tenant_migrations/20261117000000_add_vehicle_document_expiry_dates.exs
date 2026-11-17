defmodule Fleetms.Repo.TenantMigrations.AddVehicleDocumentExpiryDates do
  use Ecto.Migration

  def change do
    alter table(:vehicles, prefix: prefix()) do
      add :registration_expiry_date, :date
      add :insurance_expiry_date, :date
      add :periodic_inspection_expiry_date, :date
    end
  end
end
