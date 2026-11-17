defmodule Fleetms.Integrations.SharePoint.Config do
  @moduledoc """
  Validates the runtime settings required by the SharePoint data integration.

  This module deliberately does not perform authentication or Graph requests.
  Credentials and resource identifiers must be supplied by deployment
  environment variables and must never be committed to source control.
  """

  # The first rollout stage reads the Vehicles list only. Other list IDs and
  # the document-library drive are optional until their modules are connected.
  @required_sharepoint_keys ~w(
    MICROSOFT_TENANT_ID
    MICROSOFT_CLIENT_ID
    MICROSOFT_CLIENT_SECRET
    SHAREPOINT_SITE_ID
    SHAREPOINT_LIST_VEHICLES_ID
  )

  @optional_sharepoint_keys ~w(
    SHAREPOINT_DRIVE_ID
    SHAREPOINT_LIST_CITIES_ID
    SHAREPOINT_LIST_PROJECTS_ID
    SHAREPOINT_LIST_WORKSHOPS_ID
    SHAREPOINT_LIST_DRIVERS_ID
    SHAREPOINT_LIST_VEHICLE_ASSIGNMENTS_ID
    SHAREPOINT_LIST_BREAKDOWN_REPORTS_ID
    SHAREPOINT_LIST_WORK_ORDERS_ID
    SHAREPOINT_LIST_INVOICES_ID
    SHAREPOINT_LIST_APPROVAL_RECORDS_ID
    SHAREPOINT_LIST_VEHICLE_HISTORY_ID
    SHAREPOINT_LIST_AUDIT_LOG_ID
  )

  @type settings :: %{
          adapter: :sharepoint | :demo,
          tenant_id: String.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          site_id: String.t() | nil,
          drive_id: String.t() | nil,
          list_ids: map()
        }

  @spec load((String.t() -> String.t() | nil), atom()) ::
          {:ok, settings()} | {:error, String.t()}
  def load(get_env \\ &System.get_env/1, runtime_env \\ :prod) do
    adapter = get_env.("FLEET_DATA_ADAPTER")

    case {adapter, runtime_env} do
      {"demo", :prod} ->
        {:error, "FLEET_DATA_ADAPTER=demo is not allowed in production"}

      {"demo", _} ->
        {:ok, empty_settings(:demo)}

      {"sharepoint", _} ->
        load_sharepoint(get_env)

      {nil, :prod} ->
        {:error, "FLEET_DATA_ADAPTER must be explicitly set in production"}

      {nil, _} ->
        {:error, "FLEET_DATA_ADAPTER must be explicitly set to demo or sharepoint"}

      {_other, _} ->
        {:error, "FLEET_DATA_ADAPTER must be demo or sharepoint"}
    end
  end

  defp load_sharepoint(get_env) do
    values =
      Map.new(@required_sharepoint_keys ++ @optional_sharepoint_keys, fn key ->
        {key, get_env.(key)}
      end)

    missing =
      @required_sharepoint_keys
      |> Enum.filter(fn key ->
        value = values[key]
        is_nil(value) or String.trim(value) == ""
      end)

    case missing do
      [] ->
        {:ok,
         %{
           adapter: :sharepoint,
           tenant_id: values["MICROSOFT_TENANT_ID"],
           client_id: values["MICROSOFT_CLIENT_ID"],
           client_secret: values["MICROSOFT_CLIENT_SECRET"],
           site_id: values["SHAREPOINT_SITE_ID"],
           drive_id: blank_to_nil(values["SHAREPOINT_DRIVE_ID"]),
           list_ids: %{
             cities: blank_to_nil(values["SHAREPOINT_LIST_CITIES_ID"]),
             projects: blank_to_nil(values["SHAREPOINT_LIST_PROJECTS_ID"]),
             workshops: blank_to_nil(values["SHAREPOINT_LIST_WORKSHOPS_ID"]),
             drivers: blank_to_nil(values["SHAREPOINT_LIST_DRIVERS_ID"]),
             vehicles: values["SHAREPOINT_LIST_VEHICLES_ID"],
             vehicle_assignments: blank_to_nil(values["SHAREPOINT_LIST_VEHICLE_ASSIGNMENTS_ID"]),
             breakdown_reports: blank_to_nil(values["SHAREPOINT_LIST_BREAKDOWN_REPORTS_ID"]),
             work_orders: blank_to_nil(values["SHAREPOINT_LIST_WORK_ORDERS_ID"]),
             invoices: blank_to_nil(values["SHAREPOINT_LIST_INVOICES_ID"]),
             approval_records: blank_to_nil(values["SHAREPOINT_LIST_APPROVAL_RECORDS_ID"]),
             vehicle_history: blank_to_nil(values["SHAREPOINT_LIST_VEHICLE_HISTORY_ID"]),
             audit_log: blank_to_nil(values["SHAREPOINT_LIST_AUDIT_LOG_ID"])
           }
         }}

      keys ->
        {:error, "Missing SharePoint settings: " <> Enum.join(keys, ", ")}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp empty_settings(adapter) do
    %{
      adapter: adapter,
      tenant_id: nil,
      client_id: nil,
      client_secret: nil,
      site_id: nil,
      drive_id: nil,
      list_ids: %{}
    }
  end
end
