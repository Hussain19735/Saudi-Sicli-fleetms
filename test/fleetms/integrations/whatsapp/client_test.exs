defmodule Fleetms.Integrations.WhatsApp.ClientTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.WhatsApp.Client

  @settings %{
    enabled: true,
    access_token: "test-token",
    phone_number_id: "123456789",
    api_version: "v23.0"
  }

  test "sends an approved template and returns the provider message ID" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v23.0/123456789/messages"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["messaging_product"] == "whatsapp"
      assert payload["to"] == "966500000000"
      assert payload["type"] == "template"
      assert payload["template"]["name"] == "vehicle_expiry_notice"
      assert payload["template"]["language"]["code"] == "ar"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"messages" => [%{"id" => "wamid.test"}]}))
    end)

    assert {:ok, %{message_id: "wamid.test"}} =
             Client.send_template(
               @settings,
               "+966500000000",
               "vehicle_expiry_notice",
               "ar",
               [],
               req_options: [plug: {Req.Test, __MODULE__}]
             )
  end

  test "does not make a request for an invalid recipient or template" do
    assert {:error, :invalid_recipient_phone} =
             Client.send_template(@settings, "12345", "vehicle_expiry_notice", "ar")

    assert {:error, :invalid_template_name} =
             Client.send_template(@settings, "+966500000000", "Vehicle Expiry", "ar")
  end

  test "does not send when WhatsApp is not configured" do
    assert {:error, :whatsapp_not_configured} =
             Client.send_template(%{enabled: false}, "+966500000000", "vehicle_expiry_notice", "ar")
  end

  test "rejects malformed template components" do
    assert {:error, :invalid_template_components} =
             Client.send_template(@settings, "+966500000000", "vehicle_expiry_notice", "ar", ["not-a-map"])
  end
end
