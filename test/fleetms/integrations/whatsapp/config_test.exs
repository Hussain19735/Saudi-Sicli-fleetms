defmodule Fleetms.Integrations.WhatsApp.ConfigTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.WhatsApp.Config

  defp env(values), do: fn key -> Map.get(values, key) end

  test "keeps WhatsApp disabled when no credentials are configured" do
    assert {:ok, %{enabled: false}} = Config.load(env(%{}))
  end

  test "loads complete server-side Cloud API settings" do
    values = %{
      "WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "server-token",
      "WHATSAPP_PHONE_NUMBER_ID" => "123456789",
      "WHATSAPP_GRAPH_API_VERSION" => "v23.0"
    }

    assert {:ok, settings} = Config.load(env(values))
    assert settings.enabled
    assert settings.phone_number_id == "123456789"
    assert settings.api_version == "v23.0"
    assert settings.access_token == "server-token"
  end

  test "reports missing setting names without exposing credentials" do
    assert {:error, message} =
             Config.load(env(%{"WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "do-not-print-this"}))

    assert message =~ "WHATSAPP_PHONE_NUMBER_ID"
    assert message =~ "WHATSAPP_GRAPH_API_VERSION"
    refute message =~ "do-not-print-this"
  end

  test "rejects malformed API versions and phone number IDs" do
    base = %{
      "WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "token",
      "WHATSAPP_PHONE_NUMBER_ID" => "not-a-number",
      "WHATSAPP_GRAPH_API_VERSION" => "v23.0"
    }

    assert {:error, message} = Config.load(env(base))
    assert message =~ "PHONE_NUMBER_ID"

    assert {:error, version_message} =
             Config.load(env(Map.put(base, "WHATSAPP_PHONE_NUMBER_ID", "123456") |> Map.put("WHATSAPP_GRAPH_API_VERSION", "latest")))

    assert version_message =~ "GRAPH_API_VERSION"
  end
  test "keeps automatic vehicle notifications disabled by default" do
    values = %{
      "WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "server-token",
      "WHATSAPP_PHONE_NUMBER_ID" => "123456789",
      "WHATSAPP_GRAPH_API_VERSION" => "v23.0"
    }

    assert {:ok, settings} = Config.load(env(values))
    refute settings.vehicle_expiry_notifications_enabled
  end

  test "requires an approved template name before enabling expiry notifications" do
    values = %{
      "WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "server-token",
      "WHATSAPP_PHONE_NUMBER_ID" => "123456789",
      "WHATSAPP_GRAPH_API_VERSION" => "v23.0",
      "WHATSAPP_VEHICLE_EXPIRY_NOTIFICATIONS_ENABLED" => "true"
    }

    assert {:error, message} = Config.load(env(values))
    assert message =~ "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE"
  end

  test "loads an explicitly enabled expiry template" do
    values = %{
      "WHATSAPP_CLOUD_API_ACCESS_TOKEN" => "server-token",
      "WHATSAPP_PHONE_NUMBER_ID" => "123456789",
      "WHATSAPP_GRAPH_API_VERSION" => "v23.0",
      "WHATSAPP_VEHICLE_EXPIRY_NOTIFICATIONS_ENABLED" => "true",
      "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE" => "vehicle_document_expiry_notice",
      "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE_LANGUAGE" => "ar"
    }

    assert {:ok, settings} = Config.load(env(values))
    assert settings.enabled
    assert settings.vehicle_expiry_notifications_enabled
    assert settings.vehicle_expiry_template == "vehicle_document_expiry_notice"
    assert settings.vehicle_expiry_language == "ar"
  end

end
