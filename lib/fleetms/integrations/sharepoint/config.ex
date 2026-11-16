defmodule Fleetms.Integrations.SharePoint.Config do
  @moduledoc """
  Validates the runtime settings required by the SharePoint data integration.

  This module deliberately does not perform authentication or Graph requests.
  Credentials and resource identifiers must be supplied by deployment
  environment variables and must never be committed to source control.
  """

  @required_sharepoint_keys ~w(
    MICROSOFT_TENANT_ID
    MICROSOFT_CLIENT_ID
    SHAREPOINT_SITE_ID
    SHAREPOINT_DRIVE_ID
  )

  @type settings :: %{
          adapter: :sharepoint | :demo,
          tenant_id: String.t() | nil,
          client_id: String.t() | nil,
          site_id: String.t() | nil,
          drive_id: String.t() | nil
        }

  @spec load(map(), atom()) :: {:ok, settings()} | {:error, String.t()}
  def load(env \\ System, runtime_env \\ :prod) do
    adapter = env.get_env("FLEET_DATA_ADAPTER")

    case {adapter, runtime_env} do
      {"demo", :prod} ->
        {:error, "FLEET_DATA_ADAPTER=demo is not allowed in production"}

      {"demo", _} ->
        {:ok, empty_settings(:demo)}

      {"sharepoint", _} ->
        load_sharepoint(env)

      {nil, :prod} ->
        {:error, "FLEET_DATA_ADAPTER must be explicitly set in production"}

      {nil, _} ->
        {:error, "FLEET_DATA_ADAPTER must be explicitly set to demo or sharepoint"}

      {_other, _} ->
        {:error, "FLEET_DATA_ADAPTER must be demo or sharepoint"}
    end
  end

  defp load_sharepoint(env) do
    values = Map.new(@required_sharepoint_keys, fn key -> {key, env.get_env(key)} end)

    missing =
      values
      |> Enum.filter(fn {_key, value} -> is_nil(value) or String.trim(value) == "" end)
      |> Enum.map(&elem(&1, 0))

    case missing do
      [] ->
        {:ok,
         %{
           adapter: :sharepoint,
           tenant_id: values["MICROSOFT_TENANT_ID"],
           client_id: values["MICROSOFT_CLIENT_ID"],
           site_id: values["SHAREPOINT_SITE_ID"],
           drive_id: values["SHAREPOINT_DRIVE_ID"]
         }}

      keys ->
        {:error, "Missing SharePoint settings: " <> Enum.join(keys, ", ")}
    end
  end

  defp empty_settings(adapter) do
    %{
      adapter: adapter,
      tenant_id: nil,
      client_id: nil,
      site_id: nil,
      drive_id: nil
    }
  end
end
