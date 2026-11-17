defmodule Fleetms.Repo.TenantMigrations.AddVehicleDocumentExpiryDates do
  use Ecto.Migration

  def up do
    alter table(:vehicles, prefix: prefix()) do
      add :registration_expiry_date, :date
      add :insurance_expiry_date, :date
      add :periodic_inspection_expiry_date, :date
    end
  end

  def down do
    alter table(:vehicles, prefix: prefix()) do
      remove :registration_expiry_date
      remove :insurance_expiry_date
      remove :periodic_inspection_expiry_date
    end
  end
end
