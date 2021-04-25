defmodule Funnel.Challenge do
  use Plug.Router
  use TypedStruct

  typedstruct module: Options, enforce: true do
    field :hcaptcha_secret, String.t()
    field :allow_list, module(), default: Funnel.AllowList
  end

  @hcaptcha_verify "https://hcaptcha.com/siteverify"

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass:  ["application/json"],
                     json_decoder: Jason
  plug :dispatch, builder_opts()

  put "/challenge" do
    case handle_challenge(conn.body_params, opts) do
      :ok ->
        respond(conn, 200, %{"ok" => true})
      {:error, error} ->
        respond(conn, 400, %{"error" => inspect(error)})
    end
  end

  match _ do
    send_resp(conn, 404, "Not found\n")
  end

  # Private

  @spec respond(any(), non_neg_integer(), map()) :: nil
  defp respond(conn, code, json) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, Jason.encode!(json))
  end

  @spec handle_challenge(Options.t(), map()) :: :ok | {:error, any()}
  defp handle_challenge(opts, %{"response" => response, "source" => source})
  when is_binary(response) and is_binary(source) do
    body = "response=#{response}&secret=#{opts.hcaptcha_secret}"
    {:ok, 200, _, ref} = :hackney.post(@hcaptcha_verify, [], body)
    {:ok, result} = :hackney.body(ref)
    case Jason.decode!(result) do
      %{"success" => true} ->
        allow_email(opts, source)
      %{"error-codes" => codes} ->
        {:error, {:hcaptcha_error, codes}}
    end
  end

  defp handle_challenge(_, _) do
    {:error, :invalid_body}
  end

  @spec allow_email(Options.t(), String.t()) :: :ok | {:error, any()}
  defp allow_email(opts, source) do
    case FunnelSMTP.parse_mail_path("<#{source}}>", :mail) do
      {:ok, :null} ->
        {:error, {:invalid_email, source}}
      {:ok, source} ->
        opts.allow_list.add(source)
      error ->
        error
    end
  end
end
