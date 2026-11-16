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

  test "loads SharePoint identifiers from environment values" do
    values = %{
      "FLEET_DATA_ADAPTER" => "sharepoint",
      "MICROSOFT_TENANT_ID" => "tenant",
      "MICROSOFT_CLIENT_ID" => "client",
      "MICROSOFT_CLIENT_SECRET" => "secret",
      "SHAREPOINT_SITE_ID" => "site",
      "SHAREPOINT_DRIVE_ID" => "drive"
    }

    assert {:ok, settings} = Config.load(env(values), :prod)
    assert settings.adapter == :sharepoint
    assert settings.site_id == "site"
    assert settings.drive_id == "drive"
  end
end
