defmodule Fleetms.Integrations.SharePoint.Graph do
  @moduledoc """
  Minimal Microsoft Graph v1.0 client for SharePoint lists and document-library
  uploads. Uses application credentials supplied at runtime; no token or secret
  is returned from this module.

  This client is an integration foundation. It does not replace authorization
  checks, project/city scoping, audit logging, or business validation.
  """

  alias Fleetms.Integrations.SharePoint.Config

  @graph_base "https://graph.microsoft.com/v1.0"

  @type graph_error :: {:error, {:graph_request_failed, non_neg_integer() | atom()}}

  @spec access_token(Config.settings()) :: {:ok, String.t()} | graph_error()
  def access_token(%{adapter: :sharepoint} = settings) do
    url =
      "https://login.microsoftonline.com/" <>
        URI.encode(settings.tenant_id) <> "/oauth2/v2.0/token"

    form = [
      grant_type: "client_credentials",
      client_id: settings.client_id,
      client_secret: settings.client_secret,
      scope: "https://graph.microsoft.com/.default"
    ]

    case Req.post(url, form: form, receive_timeout: 20_000) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}}
      when is_binary(token) ->
        {:ok, token}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:graph_request_failed, status}}

      {:error, reason} ->
        {:error, {:graph_request_failed, error_kind(reason)}}
    end
  end

  @spec list_items(Config.settings(), String.t(), keyword()) ::
          {:ok, [map()]} | graph_error()
  def list_items(settings, list_id, opts \\ []) do
    query = Keyword.get(opts, :query, "$expand=fields")
    url = "#{@graph_base}/sites/#{segment(settings.site_id)}/lists/#{segment(list_id)}/items?#{query}"

    with {:ok, token} <- access_token(settings),
         {:ok, response} <- graph_get(url, token) do
      collect_pages(response, token, [])
    end
  end

  @spec create_item(Config.settings(), String.t(), map()) ::
          {:ok, map()} | graph_error()
  def create_item(settings, list_id, fields) when is_map(fields) do
    url = "#{@graph_base}/sites/#{segment(settings.site_id)}/lists/#{segment(list_id)}/items"

    with {:ok, token} <- access_token(settings),
         {:ok, %Req.Response{status: status, body: body}} <-
           Req.post(url,
             json: %{fields: fields},
             headers: auth_headers(token),
             receive_timeout: 20_000
           ),
         true <- status in 200..299 do
      {:ok, body}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:graph_request_failed, status}}
      {:error, _} = error -> normalize_error(error)
      false -> {:error, {:graph_request_failed, :unexpected_response}}
    end
  end

  @spec update_item_fields(Config.settings(), String.t(), String.t(), map(), String.t() | nil) ::
          :ok | graph_error()
  def update_item_fields(settings, list_id, item_id, fields, etag \\ nil)
      when is_map(fields) do
    url =
      "#{@graph_base}/sites/#{segment(settings.site_id)}/lists/#{segment(list_id)}/items/#{segment(item_id)}/fields"

    with {:ok, token} <- access_token(settings),
         {:ok, %Req.Response{status: status}} <-
           Req.patch(url,
             json: fields,
             headers: auth_headers(token, etag),
             receive_timeout: 20_000
           ),
         true <- status in 200..299 do
      :ok
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:graph_request_failed, status}}
      {:error, _} = error -> normalize_error(error)
      false -> {:error, {:graph_request_failed, :unexpected_response}}
    end
  end

  @spec upload_document(Config.settings(), String.t(), String.t(), binary(), String.t()) ::
          {:ok, map()} | graph_error()
  def upload_document(settings, filename, content_type, binary, parent_path \\ "")
      when is_binary(binary) do
    safe_name = segment(filename)
    safe_parent =
      parent_path
      |> String.split("/", trim: true)
      |> Enum.map(&segment/1)
      |> Enum.join("/")

    path = [safe_parent, safe_name] |> Enum.reject(&(&1 == "")) |> Enum.join("/")
    url = "#{@graph_base}/drives/#{segment(settings.drive_id)}/root:/#{path}:/content"

    with {:ok, token} <- access_token(settings),
         {:ok, %Req.Response{status: status, body: body}} <-
           Req.put(url,
             body: binary,
             headers: auth_headers(token) ++ [{"content-type", content_type}],
             receive_timeout: 120_000
           ),
         true <- status in 200..299 do
      {:ok, body}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:graph_request_failed, status}}
      {:error, _} = error -> normalize_error(error)
      false -> {:error, {:graph_request_failed, :unexpected_response}}
    end
  end

  defp graph_get(url, token) do
    case Req.get(url, headers: auth_headers(token), receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:graph_request_failed, status}}

      {:error, reason} ->
        {:error, {:graph_request_failed, error_kind(reason)}}
    end
  end

  defp collect_pages(%Req.Response{body: %{"value" => items} = body}, token, acc) do
    case body["@odata.nextLink"] do
      nil ->
        {:ok, Enum.reverse(acc) ++ items}

      url when is_binary(url) ->
        if graph_url?(url) do
          with {:ok, response} <- graph_get(url, token) do
            collect_pages(response, token, Enum.reverse(items, acc))
          end
        else
          {:error, {:graph_request_failed, :invalid_pagination_url}}
        end

      _other ->
        {:error, {:graph_request_failed, :invalid_response}}
    end
  end

  defp collect_pages(_response, _token, _acc),
    do: {:error, {:graph_request_failed, :invalid_response}}

  defp graph_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "graph.microsoft.com"} -> true
      _ -> false
    end
  end

  defp segment(value) when is_binary(value),
    do: URI.encode(value, &URI.char_unreserved?/1)

  defp segment(_value), do: ""
  
  defp auth_headers(token, etag \\ nil) do
    base = [{"authorization", "Bearer " <> token}, {"accept", "application/json"}]
    if is_binary(etag), do: base ++ [{"if-match", etag}], else: base
  end

  defp normalize_error({:error, {:graph_request_failed, _}} = error), do: error
  defp normalize_error({:error, reason}), do: {:error, {:graph_request_failed, error_kind(reason)}}

  defp error_kind(%{__struct__: module}), do: module
  defp error_kind(reason) when is_atom(reason), do: reason
  defp error_kind(_reason), do: :transport_error
end
