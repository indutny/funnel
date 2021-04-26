defmodule Funnel.Challenge do
  use Plug.Router
  use TypedStruct
  require EEx

  typedstruct module: Options, enforce: true do
    field :hcaptcha_secret, String.t()
    field :hcaptcha_sitekey, String.t()
    field :allow_list, module(), default: Funnel.AllowList
  end

  @hcaptcha_verify "https://hcaptcha.com/siteverify"

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch, builder_opts())

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, landing_page(opts.hcaptcha_sitekey))
  end

  put "/challenge" do
    case handle_challenge(opts, conn.body_params) do
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

  @spec respond(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp respond(conn, code, json) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, Jason.encode!(json))
  end

  @spec handle_challenge(Options.t(), map()) :: :ok | {:error, any()}
  defp handle_challenge(opts, %{"response" => response, "source" => source})
       when is_binary(response) and is_binary(source) do
    body = "response=#{response}&secret=#{opts.hcaptcha_secret}"

    {:ok, 200, _, res} =
      :hackney.post(
        @hcaptcha_verify,
        [
          {"Content-Type", "application/x-www-form-urlencoded"}
        ],
        body,
        [:with_body]
      )

    case Jason.decode!(res) do
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
    case FunnelSMTP.parse_mail_path("<#{source}>", :mail) do
      {:ok, :null} ->
        {:error, {:invalid_email, source}}

      {:ok, source} ->
        opts.allow_list.add(source)

      error ->
        error
    end
  end

  EEx.function_from_file(:defp, :landing_page, "www/challenge.eex", [:sitekey])
end
