defmodule Fleetms.Integrations.SharePoint.Service do
  @moduledoc """
  Authorization boundary for SharePoint repository operations.

  The actor must come from the authenticated server session. For updates, target
  scope MUST be loaded from the existing SharePoint record on the server; never
  construct it from browser parameters. Create scope must be validated against
  trusted server-side relationships before calling this module.
  """

  alias Fleetms.Integrations.SharePoint.{AccessPolicy, Repository}

  @spec authorize(map(), atom(), map()) :: :ok | {:error, :forbidden}
  def authorize(actor, action, trusted_target) do
    AccessPolicy.authorize(actor, action, trusted_target)
  end

  @spec create(map(), term(), atom(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def create(settings, actor, resource, fields, trusted_target)
      when is_map(fields) and is_map(trusted_target) do
    with :ok <- authorize(actor, :create, trusted_target) do
      Repository.create(settings, resource, fields)
    end
  end

  @spec update(map(), term(), atom(), String.t(), map(), String.t() | nil, map()) ::
          :ok | {:error, term()}
  def update(settings, actor, resource, item_id, fields, etag, trusted_existing_target)
      when is_map(fields) and is_map(trusted_existing_target) do
    with :ok <- authorize(actor, :update, trusted_existing_target) do
      Repository.update(settings, resource, item_id, fields, etag)
    end
  end

  @spec list(map(), map(), atom(), keyword(), map()) ::
          {:ok, [map()]} | {:error, term()}
  def list(settings, actor, resource, opts, trusted_scope) when is_map(trusted_scope) do
    with :ok <- authorize(actor, :read, trusted_scope) do
      Repository.list(settings, resource, opts)
    end
  end
end
