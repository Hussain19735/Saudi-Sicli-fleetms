defmodule Fleetms.Integrations.SharePoint.Repository do
  @moduledoc """
  Resource-oriented access to the provisioned SharePoint fleet lists.

  This module deliberately accepts only known resource atoms, not arbitrary
  list IDs. It is a storage adapter boundary, not a replacement for the
  authorization and project/city-scope checks required by callers.
  """

  alias Fleetms.Integrations.SharePoint.{Config, Graph}

  @resources ~w(
    cities projects workshops drivers vehicles vehicle_assignments
    breakdown_reports work_orders invoices approval_records vehicle_history audit_log
  )a

  @type resource ::
          :cities
          | :projects
          | :workshops
          | :drivers
          | :vehicles
          | :vehicle_assignments
          | :breakdown_reports
          | :work_orders
          | :invoices
          | :approval_records
          | :vehicle_history
          | :audit_log

  @spec resources() :: [resource()]
  def resources, do: @resources

  @spec list(Config.settings(), resource(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def list(settings, resource, opts \\ []) when resource in @resources do
    with {:ok, list_id} <- list_id(settings, resource) do
      Graph.list_items(settings, list_id, opts)
    end
  end

  @spec get(Config.settings(), resource(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get(settings, resource, item_id) when resource in @resources do
    with {:ok, list_id} <- list_id(settings, resource) do
      Graph.get_item(settings, list_id, item_id)
    end
  end

  @spec create(Config.settings(), resource(), map()) ::
          {:ok, map()} | {:error, term()}
  def create(settings, resource, fields) when resource in @resources and is_map(fields) do
    with {:ok, list_id} <- list_id(settings, resource) do
      Graph.create_item(settings, list_id, fields)
    end
  end

  @spec update(Config.settings(), resource(), String.t(), map(), String.t() | nil) ::
          :ok | {:error, term()}
  def update(settings, resource, item_id, fields, etag \\ nil)
      when resource in @resources and is_map(fields) do
    with {:ok, list_id} <- list_id(settings, resource) do
      Graph.update_item_fields(settings, list_id, item_id, fields, etag)
    end
  end

  defp list_id(%{adapter: :sharepoint, list_ids: ids}, resource) do
    case Map.fetch(ids, resource) do
      {:ok, id} when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, {:sharepoint_list_not_configured, resource}}
    end
  end

  defp list_id(_settings, _resource), do: {:error, :sharepoint_adapter_not_selected}
end
