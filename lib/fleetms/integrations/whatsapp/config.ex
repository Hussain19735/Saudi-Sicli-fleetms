defmodule Fleetms.Integrations.WhatsApp.Config do
  @moduledoc """
  Loads optional WhatsApp Cloud API credentials from server environment variables.

  Credentials are never committed to source control or returned in error messages.
  """

  @spec load((String.t() -> String.t() | nil)) :: {:ok, map()} | {:error, String.t()}
  def load(get_env \\ &System.get_env/1) do
    values = %{
      access_token: blank_to_nil(get_env.("WHATSAPP_CLOUD_API_ACCESS_TOKEN")),
      phone_number_id: blank_to_nil(get_env.("WHATSAPP_PHONE_NUMBER_ID")),
      api_version: blank_to_nil(get_env.("WHATSAPP_GRAPH_API_VERSION"))
    }

    notifications_enabled =
      case blank_to_nil(get_env.("WHATSAPP_VEHICLE_EXPIRY_NOTIFICATIONS_ENABLED")) do
        nil -> false
        value when value in ["true", "1"] -> true
        value when value in ["false", "0"] -> false
        _ -> :invalid
      end

    template = blank_to_nil(get_env.("WHATSAPP_VEHICLE_EXPIRY_TEMPLATE"))
    language = blank_to_nil(get_env.("WHATSAPP_VEHICLE_EXPIRY_TEMPLATE_LANGUAGE")) || "ar"

    cond do
      notifications_enabled == :invalid ->
        {:error, "WHATSAPP_VEHICLE_EXPIRY_NOTIFICATIONS_ENABLED must be true or false"}

      Enum.all?(Map.values(values), &is_nil/1) and not notifications_enabled ->
        {:ok,
         Map.merge(values, %{
           enabled: false,
           vehicle_expiry_notifications_enabled: false,
           vehicle_expiry_template: template,
           vehicle_expiry_language: language
         })}

      is_nil(values.access_token) or is_nil(values.phone_number_id) or
          is_nil(values.api_version) ->
        missing =
          [
            {"WHATSAPP_CLOUD_API_ACCESS_TOKEN", values.access_token},
            {"WHATSAPP_PHONE_NUMBER_ID", values.phone_number_id},
            {"WHATSAPP_GRAPH_API_VERSION", values.api_version}
          ]
          |> Enum.filter(fn {_key, value} -> is_nil(value) end)
          |> Enum.map(&elem(&1, 0))

        {:error, "Missing WhatsApp settings: " <> Enum.join(missing, ", ")}

      not Regex.match?(~r/^v[0-9]+\.[0-9]+$/, values.api_version) ->
        {:error, "WHATSAPP_GRAPH_API_VERSION must use the vNN.N format"}

      not Regex.match?(~r/^[0-9]+$/, values.phone_number_id) ->
        {:error, "WHATSAPP_PHONE_NUMBER_ID must contain digits only"}

      notifications_enabled and is_nil(template) ->
        {:error, "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE is required when vehicle expiry notifications are enabled"}

      not is_nil(template) and not Regex.match?(~r/^[a-z0-9_]{1,512}$/, template) ->
        {:error, "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE must be a lowercase template name"}

      not Regex.match?(~r/^[a-z]{2,3}(_[A-Z]{2})?$/, language) ->
        {:error, "WHATSAPP_VEHICLE_EXPIRY_TEMPLATE_LANGUAGE has an invalid format"}

      true ->
        {:ok,
         Map.merge(values, %{
           enabled: true,
           vehicle_expiry_notifications_enabled: notifications_enabled,
           vehicle_expiry_template: template,
           vehicle_expiry_language: language
         })}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
