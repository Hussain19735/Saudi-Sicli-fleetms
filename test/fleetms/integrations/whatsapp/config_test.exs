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
end
