defmodule Fleetms.Integrations.SharePoint.ConfigTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.SharePoint.Config

  defp env(values) do
    fn key -> Map.get(values, key) end
  end

  test "requires an explicit adapter in production" do
    assert {:error, message} = Config.load(env(%{}), :prod)
    assert message =~ "explicitly set"
  end

  test "does not allow demo storage in production" do
    assert {:error, message} = Config.load(env(%{"FLEET_DATA_ADAPTER" => "demo"}), :prod)
    assert message =~ "not allowed in production"
  end

  test "accepts explicitly selected demo storage outside production" do
    assert {:ok, %{adapter: :demo}} =
             Config.load(env(%{"FLEET_DATA_ADAPTER" => "demo"}), :dev)
  end

  test "reports missing SharePoint settings without exposing credentials" do
    assert {:error, message} =
             Config.load(env(%{"FLEET_DATA_ADAPTER" => "sharepoint"}), :prod)

    assert message =~ "MICROSOFT_TENANT_ID"
    assert message =~ "SHAREPOINT_SITE_ID"
  end

  test "accepts the first-stage vehicle connection without later module lists or a document drive" do
    values = %{
      "FLEET_DATA_ADAPTER" => "sharepoint",
      "MICROSOFT_TENANT_ID" => "tenant",
      "MICROSOFT_CLIENT_ID" => "client",
      "MICROSOFT_CLIENT_SECRET" => "secret",
      "SHAREPOINT_SITE_ID" => "site",
      "SHAREPOINT_LIST_VEHICLES_ID" => "vehicles"
    }

    assert {:ok, settings} = Config.load(env(values), :prod)
    assert settings.adapter == :sharepoint
    assert settings.site_id == "site"
    assert settings.drive_id == nil
    assert settings.list_ids.vehicles == "vehicles"
    assert settings.list_ids.drivers == nil
    assert settings.list_ids.invoices == nil
  end

  test "requires the vehicles list for the first SharePoint rollout stage" do
    values = %{
      "FLEET_DATA_ADAPTER" => "sharepoint",
      "MICROSOFT_TENANT_ID" => "tenant",
      "MICROSOFT_CLIENT_ID" => "client",
      "MICROSOFT_CLIENT_SECRET" => "secret",
      "SHAREPOINT_SITE_ID" => "site"
    }

    assert {:error, message} = Config.load(env(values), :prod)
    assert message =~ "SHAREPOINT_LIST_VEHICLES_ID"
  end

  test "loads SharePoint identifiers from environment values" do
    values = %{
      "FLEET_DATA_ADAPTER" => "sharepoint",
      "MICROSOFT_TENANT_ID" => "tenant",
      "MICROSOFT_CLIENT_ID" => "client",
      "MICROSOFT_CLIENT_SECRET" => "secret",
      "SHAREPOINT_SITE_ID" => "site",
      "SHAREPOINT_DRIVE_ID" => "drive",
      "SHAREPOINT_LIST_CITIES_ID" => "cities",
      "SHAREPOINT_LIST_PROJECTS_ID" => "projects",
      "SHAREPOINT_LIST_WORKSHOPS_ID" => "workshops",
      "SHAREPOINT_LIST_DRIVERS_ID" => "drivers",
      "SHAREPOINT_LIST_VEHICLES_ID" => "vehicles",
      "SHAREPOINT_LIST_VEHICLE_ASSIGNMENTS_ID" => "assignments",
      "SHAREPOINT_LIST_BREAKDOWN_REPORTS_ID" => "reports",
      "SHAREPOINT_LIST_WORK_ORDERS_ID" => "orders",
      "SHAREPOINT_LIST_INVOICES_ID" => "invoices",
      "SHAREPOINT_LIST_APPROVAL_RECORDS_ID" => "approvals",
      "SHAREPOINT_LIST_VEHICLE_HISTORY_ID" => "history",
      "SHAREPOINT_LIST_AUDIT_LOG_ID" => "audit"
    }

    assert {:ok, settings} = Config.load(env(values), :prod)
    assert settings.adapter == :sharepoint
    assert settings.site_id == "site"
    assert settings.drive_id == "drive"
    assert settings.list_ids.cities == "cities"
    assert settings.list_ids.audit_log == "audit"
  end
end
