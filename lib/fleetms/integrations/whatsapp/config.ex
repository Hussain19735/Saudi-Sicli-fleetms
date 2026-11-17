defmodule Fleetms.Integrations.WhatsApp.Config do
  @moduledoc """
  Loads optional WhatsApp Cloud API credentials from server environment variables.

  Credentials are never committed to source control or returned in error messages.
  """

  @type settings :: %{
          enabled: boolean(),
          access_token: String.t() | nil,
          phone_number_id: String.t() | nil,
          api_version: String.t() | nil
        }

  @spec load((String.t() -> String.t() | nil)) :: {:ok, settings()} | {:error, String.t()}
  def load(get_env \\ &System.get_env/1) do
    values = %{
      access_token: blank_to_nil(get_env.("WHATSAPP_CLOUD_API_ACCESS_TOKEN")),
      phone_number_id: blank_to_nil(get_env.("WHATSAPP_PHONE_NUMBER_ID")),
      api_version: blank_to_nil(get_env.("WHATSAPP_GRAPH_API_VERSION"))
    }

    cond do
      Enum.all?(Map.values(values), &is_nil/1) ->
        {:ok, Map.put(values, :enabled, false)}

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

      true ->
        {:ok, Map.put(values, :enabled, true)}
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
