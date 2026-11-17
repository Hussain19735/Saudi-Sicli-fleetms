defmodule Fleetms.Integrations.WhatsApp.Client do
  @moduledoc """
  Minimal server-side client for WhatsApp Business Platform Cloud API.

  This first integration stage sends approved message templates only. It does
  not send free-form text, choose recipients, or trigger fleet notifications.
  Callers must authorize and resolve recipients before invoking this module.
  """

  @phone_pattern ~r/^\\+[1-9][0-9]{7,14}$/
  @template_pattern ~r/^[a-z0-9_]{1,512}$/
  @language_pattern ~r/^[a-z]{2,3}(_[A-Z]{2})?$/

  @type result :: {:ok, %{message_id: String.t()}} | {:error, term()}

  @spec send_template(map(), String.t(), String.t(), String.t(), [map()], keyword()) ::
          result()
  def send_template(settings, recipient, template_name, language, components \\ [], opts \\ [])

  def send_template(%{enabled: true} = settings, recipient, template_name, language, components, opts)
      when is_list(components) and is_list(opts) do
    with {:ok, to} <- normalize_recipient(recipient),
         :ok <- validate_template(template_name),
         :ok <- validate_language(language),
         :ok <- validate_components(components),
         {:ok, response} <- post_template(settings, to, template_name, language, components, opts),
         {:ok, message_id} <- message_id(response) do
      {:ok, %{message_id: message_id}}
    end
  end

  def send_template(%{enabled: false}, _recipient, _template, _language, _components, _opts),
    do: {:error, :whatsapp_not_configured}

  def send_template(_settings, _recipient, _template, _language, _components, _opts),
    do: {:error, :invalid_whatsapp_settings}

  @doc false
  def build_template_payload(to, template_name, language, components \\ []) do
    with {:ok, normalized_to} <- normalize_recipient(to),
         :ok <- validate_template(template_name),
         :ok <- validate_language(language),
         :ok <- validate_components(components) do
      template = %{name: template_name, language: %{code: language}}
      template = if components == [], do: template, else: Map.put(template, :components, components)

      {:ok,
       %{
         messaging_product: "whatsapp",
         recipient_type: "individual",
         to: normalized_to,
         type: "template",
         template: template
       }}
    end
  end

  defp post_template(settings, to, template_name, language, components, opts) do
    with {:ok, payload} <- build_template_payload(to, template_name, language, components),
         true <- valid_settings?(settings) do
      url =
        "https://graph.facebook.com/#{settings.api_version}/" <>
          "#{settings.phone_number_id}/messages"

      request_options =
        [
          json: payload,
          headers: [{"authorization", "Bearer " <> settings.access_token}],
          receive_timeout: 20_000,
          retry: false
        ]
        |> Keyword.merge(Keyword.get(opts, :req_options, []))

      case Req.post(url, request_options) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:whatsapp_api_error, status}}

        {:error, reason} ->
          {:error, {:whatsapp_transport_error, error_kind(reason)}}
      end
    else
      false -> {:error, :invalid_whatsapp_settings}
      {:error, _} = error -> error
    end
  end

  defp valid_settings?(%{
         access_token: token,
         phone_number_id: phone_number_id,
         api_version: api_version
       }) do
    is_binary(token) and token != "" and
      is_binary(phone_number_id) and Regex.match?(~r/^[0-9]+$/, phone_number_id) and
      is_binary(api_version) and Regex.match?(~r/^v[0-9]+\\.[0-9]+$/, api_version)
  end

  defp valid_settings?(_settings), do: false

  defp normalize_recipient(recipient) when is_binary(recipient) do
    if Regex.match?(@phone_pattern, recipient) do
      {:ok, String.replace_prefix(recipient, "+", "")}
    else
      {:error, :invalid_recipient_phone}
    end
  end

  defp normalize_recipient(_recipient), do: {:error, :invalid_recipient_phone}

  defp validate_template(name) when is_binary(name) do
    if Regex.match?(@template_pattern, name),
      do: :ok,
      else: {:error, :invalid_template_name}
  end

  defp validate_template(_name), do: {:error, :invalid_template_name}

  defp validate_language(language) when is_binary(language) do
    if Regex.match?(@language_pattern, language),
      do: :ok,
      else: {:error, :invalid_template_language}
  end

  defp validate_language(_language), do: {:error, :invalid_template_language}

  defp validate_components(components) when is_list(components) do
    if Enum.all?(components, &is_map/1),
      do: :ok,
      else: {:error, :invalid_template_components}
  end

  defp validate_components(_components), do: {:error, :invalid_template_components}

  defp message_id(%{"messages" => [%{"id" => id} | _]}) when is_binary(id) and id != "",
    do: {:ok, id}

  defp message_id(_response), do: {:error, :invalid_whatsapp_response}

  defp error_kind(%{__struct__: module}), do: module
  defp error_kind(reason) when is_atom(reason), do: reason
  defp error_kind(_reason), do: :transport_error
end
