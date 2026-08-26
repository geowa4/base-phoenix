# Technical Specification — Elixir + Phoenix Batteries-Included Starter Template

**Status:** Adopted. Verified against primary sources as of August 24, 2026. Re-verification cadence: quarterly. Target platform: Fly.io. Canonical naming placeholders: `my_app` (OTP app / snake_case), `MyApp` (domain module), `MyAppWeb` (web module).

## TL;DR

- This template is a GitHub template repository that clones to a production-shaped Elixir 1.20 / Phoenix 1.8 LiveView application with a single `mix my_app.rename` bootstrap, a five-layer quality gate unified under `mix precommit`, first-class Fly.io blue-green deployment, Resend email (outbound + inbound webhook), an authenticated `/inbox` LiveView demonstrating the inbound data flow end to end, Prometheus metrics on a private port, OpenTelemetry, and a hardened `phx.gen.auth` stack.
- Coding-agent support is a first-class, decided-in capability: **AGENTS.md** is the canonical instruction file (an open Linux Foundation standard read natively by Codex, Cursor, GitHub Copilot, and Jules, among others), a one-line **CLAUDE.md** `@AGENTS.md` bridge wires Claude Code, **usage_rules** keeps dependency rules synchronized into AGENTS.md, and **Tidewave** provides a dev-only MCP server exposing runtime introspection to agents.
- All decisions are final and encoded here as declarative build instructions; alternatives were evaluated and rejected on a minimal-dependency, cross-platform-safe, primary-source-verified basis.

## Versions

All versions were re-verified against Hex and primary release notes on the status date. The notes column records the reason a floor or pin exists.

| Component | Version | Notes |
|---|---|---|
| Elixir | 1.20.3 | Set-theoretic type checker surfaced by `compile --warnings-as-errors` |
| Erlang/OTP | 28.3 | |
| Phoenix | `~> 1.8.11` | Floor above CVE-2026-32689 (fixed 1.8.6); generates AGENTS.md + `precommit` alias |
| Phoenix LiveView | `~> 1.2.9` | Floors CVE-2026-58228 (fixed 1.2.7) and CVE-2026-64941 (fixed 1.2.9) |
| Bandit | `~> 1.0` | Sole web server; no Cowboy in the tree |
| ecto_sql | `~> 3.13` | `Repo.transact/2` |
| postgrex | `~> 0.20` | Pre-1.0 |
| PostgreSQL | 18 | CI service image `postgres:18` |
| Swoosh | `~> 1.20` | `Swoosh.Adapters.Resend` first-party, shipped 1.20.0 via PR #1089; current 1.27.x |
| Req | `~> 0.5` | `Swoosh.ApiClient.Req`; preferred HTTP client; pre-1.0 |
| prom_ex | 1.12.0 | |
| argon2_elixir | `~> 4.0` | Argon2id password hashing |
| opentelemetry | 1.7 | `:temporary` |
| opentelemetry_api | 1.5 | |
| opentelemetry_exporter | 1.10 | `:permanent`, listed before `opentelemetry` |
| opentelemetry_phoenix | 2.0.1 | `adapter: :bandit, liveview: true` |
| opentelemetry_bandit | 0.3.0 | Pre-1.0 |
| opentelemetry_ecto | 1.2.0 | |
| logger_json | `~> 7.0` | Prod JSON formatter |
| tailwind (wrapper) | 0.5.1 | Tailwind v4 + daisyUI, no Node |
| esbuild (wrapper) | `~> 0.10` | No Node |
| PhoenixTest | 0.12.1 | Decided-in; pre-1.0 |
| Igniter | 0.8.0 | Post-clone `mix igniter.install` add-ons only |
| igniter_new | 0.5.34 | |
| Assent | `~> 0.3` | Documented add-on |
| Cachex | 4.1.1 | Deferred add-on |
| credo | `~> 1.7` | `--strict` |
| dialyxir | `~> 1.4` | CI-only Dialyzer job |
| **usage_rules** | **`~> 1.2` (1.2.7)** | **Dev/test; Igniter-installed; syncs dependency rules into AGENTS.md** |
| **tidewave** | **`~> 0.9`** | **Dev-only MCP server; single plug in the dev endpoint** |

---

## §1 Project scaffolding

The template is published as a **GitHub template repository**. A new project is created with GitHub's "Use this template" flow, cloned, and then personalized by a single first-run Mix task:

```
mix my_app.rename --otp <otp_app> --module <ModuleName>
```

`Mix.Tasks.MyApp.Rename` (shipped in `lib/mix/tasks/my_app.rename.ex`) performs an in-place rename:

```elixir
defmodule Mix.Tasks.MyApp.Rename do
  @shortdoc "Renames the starter template to your app's names (run once)"
  use Mix.Task

  @switches [otp: :string, module: :string]
  @skip_dirs ~w(_build deps .git priv/static assets/node_modules node_modules)

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    otp = opts[:otp] || Mix.raise("--otp <snake_case_otp_app> is required")
    module = opts[:module] || Mix.raise("--module <PascalCaseModule> is required")

    validate_snake_case!(otp)
    validate_pascal_case!(module)

    # Substitution order matters: the most specific token first, so that
    # MyAppWeb is not partially rewritten by the MyApp rule.
    subs = [
      {"MyAppWeb", module <> "Web"},
      {"MyApp", module},
      {"my_app", otp}
    ]

    files = collect_files(".")

    # 1. Rewrite file contents.
    Enum.each(files, fn path -> rewrite_contents(path, subs) end)

    # 2. Rename paths, longest path first so parent renames do not invalidate
    #    child paths still queued.
    files
    |> Enum.filter(&String.contains?(&1, "my_app"))
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.each(fn path -> rename_path(path, otp) end)

    # 3. Delete this task so it cannot run twice.
    File.rm!(__ENV__.file)

    Mix.shell().info("""

    Renamed to #{module} (#{otp}). Next steps:

        mix setup
        mix usage_rules.sync
        mix precommit
        mix phx.server
    """)
  end

  defp validate_snake_case!(s) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, s) do
      Mix.raise("--otp must be snake_case, got: #{inspect(s)}")
    end
  end

  defp validate_pascal_case!(s) do
    unless Regex.match?(~r/^[A-Z][A-Za-z0-9]*$/, s) do
      Mix.raise("--module must be PascalCase, got: #{inspect(s)}")
    end
  end

  defp collect_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.reject(fn path -> Enum.any?(@skip_dirs, &String.contains?(path, &1)) end)
  end

  defp rewrite_contents(path, subs) do
    case File.read(path) do
      {:ok, contents} ->
        new = Enum.reduce(subs, contents, fn {from, to}, acc ->
          String.replace(acc, from, to)
        end)
        if new != contents, do: File.write!(path, new)

      {:error, _} ->
        :ok
    end
  end

  defp rename_path(path, otp) do
    new_path = String.replace(path, "my_app", otp)
    if new_path != path do
      File.mkdir_p!(Path.dirname(new_path))
      File.rename!(path, new_path)
    end
  end
end
```

`AGENTS.md` and `CONTRIBUTING.md` contain `my_app`/`MyApp` references (in commands, module names, and code examples) and are ordinary tracked files, so the rename task rewrites them automatically; `CLAUDE.md` is a single `@AGENTS.md` import line and needs no rewriting. No separate step is required for the agent files.

**License:** the template repository is MIT-licensed. A `LICENSE` file at the repository root carries the standard MIT text (per choosealicense.com/licenses/mit) with the year and copyright holder filled in; projects created from the template inherit the file and update the copyright line at bootstrap. The file contains no `my_app` tokens, so the rename task leaves it untouched.

```text
MIT License

Copyright (c) <year> <copyright holder>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Alternatives evaluated and rejected:** `mix_templates` (dormant, unmaintained); `phx.new` template overrides (insufficient depth — cannot express the multi-file production wiring this template requires); Igniter as the primary scaffolder (Igniter is a composable code-modification tool, not a repository cloner). Igniter is retained for `mix igniter.install` of decided-in and optional add-ons after clone.

## §2 Lint & type stack and the `mix precommit` quality gate

Five decided quality layers run on every change:

1. `mix format --check-formatted`
2. `mix deps.unlock --check-unused`
3. `mix compile --warnings-as-errors` (surfaces the Elixir 1.20 set-theoretic type checker)
4. `mix credo --strict`
5. `mix dialyzer` — Dialyzer is retained because the built-in set-theoretic checker does not yet consume `@spec`; it runs as a **separate, required CI job** with a PLT cache, not inside `precommit`.

Phoenix 1.8 generates a `precommit` alias in new apps (the changelog entry "`[phx.new] Add mix precommit alias`"). The template standardizes that alias to the following contents in `mix.exs`. This single command is the quality gate referenced by AGENTS.md, the documentation, and the pre-commit hook:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["tailwind my_app", "esbuild my_app"],
    "assets.deploy": [
      "tailwind my_app --minify",
      "esbuild my_app --minify",
      "phx.digest"
    ],
    precommit: [
      "format --check-formatted",
      "deps.unlock --check-unused",
      "compile --warnings-as-errors",
      "credo --strict",
      "test"
    ]
  ]
end
```

Dialyzer is intentionally excluded from `precommit` (it belongs to the dedicated CI job). The name `mix precommit` is used consistently everywhere in this specification; no `mix check` naming appears.

A lightweight local hook enforces the fast subset of the gate before each commit. `.githooks/pre-commit`:

```sh
#!/usr/bin/env sh
set -e
mix format --check-formatted
mix credo --strict
```

Enabled per-clone with `git config core.hooksPath .githooks`. No `git_hooks` dependency is added; the hook is a plain shell script.

## §3 PostgreSQL

The default Ecto `migration_lock` remains `:table_lock`; `pg_advisory_lock` is documented as an opt-in for teams that require it. Concurrent index creation, which cannot run inside a transaction, uses:

```elixir
defmodule MyApp.Repo.Migrations.AddIndexConcurrentlyToWidgets do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:widgets, [:account_id], concurrently: true)
  end
end
```

**Expand-contract discipline is required** because blue-green deployment runs old and new code against the same database simultaneously. Every schema change is decomposed into an additive "expand" migration deployed first, a code rollout, and a later "contract" migration that removes the old shape. `CHECK` constraints are added with `validate: false` (`NOT VALID`) and validated in a subsequent migration:

```elixir
def change do
  # Expand migration:
  execute(
    "ALTER TABLE widgets ADD CONSTRAINT widgets_qty_positive CHECK (qty > 0) NOT VALID",
    "ALTER TABLE widgets DROP CONSTRAINT widgets_qty_positive"
  )
end
```

```elixir
def change do
  # Later migration:
  execute(
    "ALTER TABLE widgets VALIDATE CONSTRAINT widgets_qty_positive",
    ""
  )
end
```

Long-running statements are bounded with `lock_timeout` and `statement_timeout` set per migration where appropriate.

The release migrator, invoked by Fly's `release_command`, lives in `lib/my_app/release.ex`:

```elixir
defmodule MyApp.Release do
  @moduledoc "Release tasks run inside the Fly deploy release command."
  @app :my_app

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
```

## §4 Authentication

Generated with:

```
mix phx.gen.auth --live --hashing-lib argon2
```

Both **magic-link and password authentication are first-class**. Phoenix 1.8's generator ships magic links out of the box ("Introduce magic links (passwordless auth) and \"sudo mode\" to `mix phx.gen.auth`") and includes credential pre-stuffing defense: login is required at confirmation. The generator's verbatim rationale is preserved in the code comments. The generated `UserAuth` plug/hook, session rotation on login, and log-out-everywhere behavior are all kept unchanged.

## §5 Outbound email (Resend)

The first-party `Swoosh.Adapters.Resend` (Swoosh `~> 1.20`) is used with `Swoosh.ApiClient.Req` (Req is already in the tree). The community `resend` package is explicitly not used.

`config/config.exs`:

```elixir
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Resend
config :swoosh, api_client: Swoosh.ApiClient.Req
```

`config/runtime.exs` (prod):

```elixir
config :my_app, MyApp.Mailer, api_key: System.fetch_env!("RESEND_API_KEY")
config :my_app, resend_api_key: System.fetch_env!("RESEND_API_KEY")
```

The second line feeds `MyApp.Resend`, the Req-based Receiving API client used by the inbox LiveView (§6). In dev, set `resend_api_key` from the same environment variable when exercising the inbox against a real Resend account; the Mailer itself stays on `Swoosh.Adapters.Local`.

`config/dev.exs` uses `Swoosh.Adapters.Local`; `config/test.exs` uses `Swoosh.Adapters.Test`. The mailer module is `MyApp.Mailer`.

## §6 Resend inbound webhook

Resend's `email.received` event is metadata-only; the message body is fetched separately from the Receiving API. Signatures are verified manually with the Svix scheme (no `svix` dependency):

- Headers: `svix-id`, `svix-timestamp`, `svix-signature`.
- Signed content is the string `"#{id}.#{timestamp}.#{body}"`, HMAC-SHA256.
- The signing secret has its `whsec_` prefix stripped and is base64-decoded to key bytes.
- The header may carry multiple space-separated `v1,<sig>` values; any constant-time match passes, compared with `Plug.Crypto.secure_compare/2`.
- A ±300 second timestamp tolerance is enforced.

Raw body capture is required for HMAC, using a `Plug.Parsers` `:body_reader`:

```elixir
defmodule MyAppWeb.Plugs.CacheRawBody do
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], fn chunks -> [body | chunks || []] end)
    {:ok, body, conn}
  end
end
```

```elixir
defmodule MyAppWeb.Plugs.VerifyResendSignature do
  import Plug.Conn
  @tolerance 300

  def init(opts), do: opts

  def call(conn, _opts) do
    with [svix_id] <- get_req_header(conn, "svix-id"),
         [svix_ts] <- get_req_header(conn, "svix-timestamp"),
         [svix_sig] <- get_req_header(conn, "svix-signature"),
         :ok <- check_timestamp(svix_ts),
         body <- raw_body(conn),
         :ok <- verify(svix_id, svix_ts, body, svix_sig) do
      conn
    else
      _ -> conn |> send_resp(401, "invalid signature") |> halt()
    end
  end

  defp raw_body(conn), do: conn.assigns.raw_body |> Enum.reverse() |> IO.iodata_to_binary()

  defp check_timestamp(ts) do
    now = System.system_time(:second)
    case Integer.parse(ts) do
      {t, _} when abs(now - t) <= @tolerance -> :ok
      _ -> :error
    end
  end

  defp verify(id, ts, body, header) do
    secret =
      Application.fetch_env!(:my_app, :resend_webhook_secret)
      |> String.replace_prefix("whsec_", "")
      |> Base.decode64!()

    signed = "#{id}.#{ts}.#{body}"
    expected = :crypto.mac(:hmac, :sha256, secret, signed) |> Base.encode64()

    header
    |> String.split(" ", trim: true)
    |> Enum.map(fn part -> part |> String.split(",", parts: 2) |> List.last() end)
    |> Enum.any?(fn sig -> Plug.Crypto.secure_compare(sig, expected) end)
    |> case do
      true -> :ok
      false -> :error
    end
  end
end
```

The controller dedupes on `svix-id` via a `webhook_events` table with a unique index, returns `200` quickly, and hands off asynchronously. `MyApp.Inbound` is the extension point: `record_event/2`, the PubSub broadcast below, and any future processing (Receiving API fetches, agent workflows) all live here. Only the `svix-id` is persisted; email metadata is never written to the database.

### Inbox LiveView (data-flow demonstration)

The template demonstrates its end-to-end data flow with one authenticated LiveView: a logged-in user sends an email from their own address to the app's Resend inbound address and watches it appear at `/inbox`. Matching is by sender: an inbound email belongs to the user whose account email equals the email's `From` address.

**Decision: nothing is stored.** Inbound email metadata (`from`, `to`, `subject`, `email_id`, `created_at`) lives only in the LiveView process. The webhook broadcasts metadata over `Phoenix.PubSub` on a per-sender topic; the LiveView backfills history on mount from Resend's List Received Emails API (`GET /emails/receiving`, cursor-paginated) and receives live updates from the broadcast. A remount simply refetches. The `webhook_events` dedupe table remains the only inbound persistence.

`MyApp.Inbound` gains normalization, topics, and the broadcast:

```elixir
defmodule MyApp.Inbound do
  @moduledoc "Inbound email fan-out and extension point. No email data is persisted."

  def subscribe(email),
    do: Phoenix.PubSub.subscribe(MyApp.PubSub, topic_for(email))

  def topic_for(email), do: "inbound_emails:" <> normalize(email)

  @doc "Extracts the bare address from `Name <addr>` forms and downcases it."
  def normalize(from) when is_binary(from) do
    case Regex.run(~r/<([^>]+)>/, from) do
      [_, addr] -> addr |> String.trim() |> String.downcase()
      nil -> from |> String.trim() |> String.downcase()
    end
  end

  @doc "Called by the webhook controller after signature verification and dedupe."
  def handle_event(%{"type" => "email.received", "data" => data}) do
    meta = %{
      id: data["email_id"],
      email_id: data["email_id"],
      from: normalize(data["from"]),
      to: data["to"] || [],
      subject: data["subject"],
      received_at: data["created_at"]
    }

    Phoenix.PubSub.broadcast(MyApp.PubSub, topic_for(meta.from), {:email_received, meta})
    :ok
  end

  def handle_event(_other), do: :ok
end
```

A minimal Req-based client wraps the Receiving API (the `RESEND_API_KEY` is read into app config in `runtime.exs`):

```elixir
defmodule MyApp.Resend do
  @moduledoc "Minimal Resend API client (Req)."
  @base_url "https://api.resend.com"

  def list_received(params \\ []) do
    [url: @base_url <> "/emails/receiving", auth: {:bearer, api_key()}, params: params]
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} -> {:ok, data}
      {:ok, %Req.Response{} = resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp api_key, do: Application.fetch_env!(:my_app, :resend_api_key)
end
```

The LiveView subscribes for the current user's address, backfills asynchronously, and holds entries in a stream — process memory only:

```elixir
defmodule MyAppWeb.InboxLive do
  use MyAppWeb, :live_view
  alias MyApp.{Inbound, Resend}

  @impl true
  def mount(_params, _session, socket) do
    user_email = Inbound.normalize(socket.assigns.current_scope.user.email)

    if connected?(socket), do: Inbound.subscribe(user_email)

    {:ok,
     socket
     |> assign(user_email: user_email, loading: true)
     |> stream(:emails, [])
     |> start_async(:backfill, fn -> Resend.list_received() end)}
  end

  @impl true
  def handle_async(:backfill, {:ok, {:ok, emails}}, socket) do
    mine =
      emails
      |> Enum.filter(&(Inbound.normalize(&1["from"]) == socket.assigns.user_email))
      |> Enum.map(&entry/1)

    {:noreply, socket |> assign(loading: false) |> stream(:emails, mine)}
  end

  def handle_async(:backfill, _error, socket) do
    {:noreply, socket |> assign(loading: false) |> put_flash(:error, "Could not load inbox history")}
  end

  @impl true
  def handle_info({:email_received, meta}, socket) do
    {:noreply, stream_insert(socket, :emails, meta, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>Inbox</.header>
    <p class="text-sm">Emails you sent to this app's inbound address, matched by your account email.</p>
    <table id="emails" phx-update="stream">
      <tbody>
        <tr :for={{dom_id, email} <- @streams.emails} id={dom_id}>
          <td>{email.subject}</td>
          <td>{Enum.join(email.to, ", ")}</td>
          <td>{email.received_at}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp entry(%{"id" => id} = e) do
    %{
      id: id,
      email_id: id,
      from: Inbound.normalize(e["from"]),
      to: e["to"] || [],
      subject: e["subject"],
      received_at: e["created_at"]
    }
  end
end
```

Stream entries are keyed by the Resend email id, so a broadcast arriving for an email already present from backfill (or vice versa) updates in place rather than duplicating.

Route, inside the authenticated `live_session` generated by `phx.gen.auth`:

```elixir
live_session :require_authenticated_user,
  on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user]
    live "/inbox", InboxLive, :index
  end
end
```

**Security boundary:** an email's `From` header is sender-controlled and trivially spoofable. This matching is a data-flow demonstration, not authentication — inbound email content must never grant privileges, trigger account changes, or be treated as a verified statement from the matched user. There is no admin surface; every user sees only emails matched to their own address, and a spoofed `From` leaks nothing beyond the metadata the spoofer already wrote.

## §7 Health checks

Two endpoints:

- `GET /healthz/live` — always returns `200`, dependency-free (liveness).
- `GET /healthz/ready` — reads a `:persistent_term` written by a probe GenServer (readiness).

```elixir
defmodule MyApp.Health.Probe do
  use GenServer
  @key {__MODULE__, :ready?}
  @interval 10_000

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  def ready?, do: :persistent_term.get(@key, false)

  @impl true
  def init(:ok) do
    :persistent_term.put(@key, false)
    {:ok, %{}, {:continue, :probe}}
  end

  @impl true
  def handle_continue(:probe, state) do
    probe()
    schedule()
    {:noreply, state}
  end

  @impl true
  def handle_info(:probe, state) do
    probe()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :probe, @interval)

  defp probe do
    ready? =
      case Ecto.Adapters.SQL.query(MyApp.Repo, "SELECT 1", []) do
        {:ok, _} -> true
        _ -> false
      end

    :persistent_term.put(@key, ready?)
  end
end
```

```elixir
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def live(conn, _), do: send_resp(conn, 200, "ok")

  def ready(conn, _) do
    if MyApp.Health.Probe.ready?(),
      do: send_resp(conn, 200, "ready"),
      else: send_resp(conn, 503, "not ready")
  end
end
```

`fly.toml` gates routing on readiness via `[[http_service.checks]]` (`GET /healthz/ready`, interval 10s, timeout 2s, grace 10s) and observes liveness with a top-level `[[checks]]` (`GET /healthz/live`, interval 15s, timeout 2s).

## §8 Prometheus on a dedicated private port (9091)

**Decision:** a hand-rolled second Bandit listener serves `PromEx.Plug`, chosen over PromEx's built-in `:metrics_server` because that server is Cowboy-based (PromEx's standalone plug path requires `:plug` and `:plug_cowboy`, with `plug_cowboy` optional in PromEx's `mix.exs`) and would add Cowboy alongside Bandit. The minimal-dependency criterion decides.

```elixir
defmodule MyApp.PromEx do
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: MyAppWeb.Router, endpoint: MyAppWeb.Endpoint},
      PromEx.Plugins.Ecto
    ]
  end

  @impl true
  def dashboards, do: []
end
```

```elixir
defmodule MyAppWeb.MetricsEndpoint do
  use Plug.Builder
  plug PromEx.Plug, prom_ex_module: MyApp.PromEx
  plug :not_found
  def not_found(conn, _), do: Plug.Conn.send_resp(conn, 404, "not found")
end
```

Supervision tree order (`lib/my_app/application.ex`): `MyApp.PromEx` first, then `MyApp.Repo`, `DNSCluster`, `Phoenix.PubSub`, `MyApp.Health.Probe`, `MyAppWeb.Endpoint`, and finally the metrics listener:

```elixir
{Bandit, plug: MyAppWeb.MetricsEndpoint, port: String.to_integer(System.get_env("METRICS_PORT") || "9091")}
```

`fly.toml` declares `[metrics] port = 9091, path = "/metrics"`. The metrics port is never listed under `[http_service]`/`[[services]]`, so it is never publicly reachable; Fly scrapes it over the private network every 15s. No in-app authentication is needed.

## §9 OpenTelemetry

Dependencies are listed with `opentelemetry_exporter` marked `:permanent` and ordered **before** `opentelemetry` (`:temporary`) in `mix.exs`, and the releases config mirrors that order so the exporter outlives the SDK on shutdown. Setup (in `application.ex` `start/2` before the supervisor starts):

```elixir
OpentelemetryPhoenix.setup(adapter: :bandit, liveview: true)
OpentelemetryBandit.setup()
OpentelemetryEcto.setup([:my_app, :repo])
```

`OTEL_EXPORTER_OTLP_*` variables are provided through `fly secrets`. The `trace_id` is injected into `logger_json` metadata for log-trace correlation.

## §10 Scaffolding, testing & CI

A full LiveView application runs on Bandit. Assets use the Tailwind v4 wrapper + daisyUI + esbuild, with **no Node**. LiveDashboard is mounted behind authentication. The prod logger uses the `logger_json` formatter. The `/live` socket sets `longpoll: false` as defense for CVE-2026-32689 (GHSA-628h-q48j-jr6q).

Testing stack: ExUnit, Ecto SQL Sandbox, Mox, StreamData, `Phoenix.LiveViewTest`, and PhoenixTest 0.12.1. Async tests are only permitted where the SQL Sandbox owner model allows isolation.

CI is two required GitHub Actions jobs.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      db:
        image: postgres:18
        env:
          POSTGRES_PASSWORD: postgres
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5
    env:
      MIX_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/my_app_test
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.20.3"
          otp-version: "28.3"
      - uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix deps.unlock --check-unused
      - run: mix compile --warnings-as-errors
      - run: mix credo --strict
      # AGENTS.md ↔ CLAUDE.md bridge guard (see §13.5):
      - name: Verify CLAUDE.md bridge
        run: grep -qxF '@AGENTS.md' CLAUDE.md
      # usage_rules drift guard: sync is idempotent; a diff means it was not committed.
      - name: Verify usage_rules sync is current
        run: |
          mix usage_rules.sync
          git diff --exit-code AGENTS.md
      - run: mix test

  dialyzer:
    runs-on: ubuntu-latest
    env:
      MIX_ENV: dev
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.20.3"
          otp-version: "28.3"
      - uses: actions/cache@v4
        with:
          path: priv/plts
          key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-plt-
      - run: mix deps.get
      - run: mix dialyzer --format github
```

## §11 Fly.io deployment

Generated with `mix phx.gen.release --docker`. `rel/env.sh.eex` sets IPv6 and clustering:

```sh
export ERL_AFLAGS="-proto_dist inet6_tcp"
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"
export ECTO_IPV6=true
export DNS_CLUSTER_QUERY="${FLY_APP_NAME}.internal"
```

Secrets set with `fly secrets`: `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `SECRET_KEY_BASE`, and the `OTEL_*` variables.

`fly.toml` uses blue-green with the release migrator:

```toml
[deploy]
  strategy = "bluegreen"
  release_command = "/app/bin/migrate"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 1
```

Blue-green requires readiness checks and expand-contract migrations (both specified above). Because `auto_stop_machines` would kill background GenServers (the health probe, PromEx, schedulers), `min_machines_running = 1` is mandatory.

## §12 Documented add-ons

- **Assent `~> 0.3`** — OAuth/OIDC (Auth0, Cognito). A `user_identities` table keys `user_id + provider + uid` with a unique index on `{provider, uid}`; configured via environment variables; installable later with Igniter.
- **Cachex 4.1.1** — deferred; add when a real caching need appears.
- **logger_json** — alternative formatters documented for non-Fly log sinks.

**Community agent skill/plugin marketplaces (optional references, not installed):**

- `claude-code-elixir` — Claude Code plugin bundle for Elixir.
- `claude-elixir-phoenix` — Phoenix-focused Claude skills.
- `bmad-elixir` — BMAD-method Elixir agent workflows.
- `HexDocs MCP` — local embeddings-based HexDocs search server.
- `ElixirLS MCP` — ElixirLS's built-in MCP server (`find_definition`, `get_docs`, etc.; shipped in ElixirLS v0.29.x).

These are listed for awareness only. Skills are executable instructions that can direct an agent to run commands, so any third-party skill content is reviewed before adoption.

---

## §13 Coding-agent support

This template treats coding agents as first-class users. The design has one canonical instruction file, a single documented bridge for the one agent that does not read it, and two decided-in dependencies that keep the instructions accurate and give agents runtime visibility.

### 13.1 AGENTS.md is canonical

`AGENTS.md` is an open, Markdown-only standard. It originated at OpenAI in August 2025 and was donated to the Linux Foundation on December 9, 2025, co-founding the Agentic AI Foundation (AAIF); the Linux Foundation's founding announcement names the three anchor contributions as "Anthropic's Model Context Protocol (MCP), Block's goose, and OpenAI's AGENTS.md," with Amazon, Google, Microsoft, Bloomberg, and Cloudflare among the supporting members. Per that same Dec 9, 2025 press release, "AGENTS.md has already been adopted by more than 60,000 open source projects and agent frameworks including Amp, Codex, Cursor, Devin, Factory, Gemini CLI, GitHub Copilot, Jules and VS Code among others." It is schema-free (any headings are permitted — the format imposes no constraints on heading names, nesting, or order) and uses nearest-file precedence in monorepos (the AGENTS.md closest to an edited file wins).

It is read **natively** by OpenAI Codex, Cursor, GitHub Copilot coding agent, Google Jules, Zed, Amp, Windsurf, Devin, Factory, and pi.dev, among others. Two widely used agents require one line of configuration:

| Agent | AGENTS.md support | Wiring |
|---|---|---|
| Codex, Cursor, Copilot, Jules, Zed, Amp, Windsurf, pi.dev | Native | None |
| Claude Code | Reads `CLAUDE.md`, not `AGENTS.md` | `CLAUDE.md` contains `@AGENTS.md` (§13.2) |
| Aider | Config | `.aider.conf.yml` → `read: AGENTS.md` |
| Gemini CLI | Config | `.gemini/settings.json` → `{ "context": { "fileName": "AGENTS.md" } }` |

The template ships the `.aider.conf.yml` and `.gemini/settings.json` bridges above so those two agents work without manual setup.

**Codex truncation constraint:** OpenAI Codex silently truncates the combined instruction files at 32 KiB. Codex's own source defines the limit — "Maximum number of bytes of the documentation that will be embedded. Larger files are *silently truncated* to this size … `pub(crate) const PROJECT_DOC_MAX_BYTES: usize = 32 * 1024; // 32 KiB`" — and OpenAI's official Codex docs confirm the behavior: "Codex skips empty files and stops adding files once the combined size reaches the limit defined by project_doc_max_bytes (32 KiB by default)." The template's `AGENTS.md` is kept well under 32 KiB; reference material is pushed to `CONTRIBUTING.md`, HexDocs, usage_rules, and Tidewave rather than inlined. (Note: `project_doc_max_bytes` is user-configurable, and some newer Codex releases raise the default; the template does not rely on a raised limit.)

The template's `AGENTS.md` **starts from the file that `phx.new` generates** — the Phoenix 1.8.0 release states that "New applications generated with `phx.new` have an AGENTS.md containing guidelines extracted from the Phoenix.new agent" — and is **slimmed and extended** per the split defined in §13.7: always-loaded behavioral rules stay in `AGENTS.md`; reference detail moves to `CONTRIBUTING.md`. The canonical, ready-to-commit content for both files is in §13.7.

### 13.2 Claude Code bridge (CLAUDE.md)

Per Anthropic's official memory documentation, Claude Code reads `CLAUDE.md` and does **not** read `AGENTS.md`. `CLAUDE.md` supports `@path` imports; per the official docs (`code.claude.com/docs/en/memory`), "Relative paths resolve relative to the file containing the import, not the working directory. Imported files can recursively import other files, with a maximum depth of four hops. Import parsing skips Markdown code spans and fenced code blocks." (One Anthropic doc mirror states five hops; the current canonical docs state four — treat four as the safe assumption.) The documented one-line bridge is a `CLAUDE.md` whose first line is:

```
@AGENTS.md
```

A symlink (`ln -s AGENTS.md CLAUDE.md`) also works but is Unix-only — on Windows it requires administrator privileges or Developer Mode, and checkouts without either produce a plain text file containing the literal path. **Decision: the symlink is rejected for cross-platform safety.** The template ships a real `CLAUDE.md` whose entire content is the single import line:

```markdown
@AGENTS.md
```

No Claude-specific content is added; anything worth telling Claude Code is worth telling every agent and therefore belongs in `AGENTS.md`.

**Memory hierarchy (highest precedence first):** enterprise/managed policy → user `~/.claude/CLAUDE.md` → project `./CLAUDE.md` → `CLAUDE.local.md` (deprecated in favor of imports, which "work better across multiple git worktrees"). Anthropic's concision guidance keeps memory files short — the official docs advise "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." The template's `CLAUDE.md` is one line because all real content lives in `AGENTS.md`.

### 13.3 usage_rules (decided-in, dev/test)

`usage_rules` (ash-project/usage_rules, `~> 1.2`, current 1.2.7) is a decided-in dev/test dependency that integrates with Igniter (already specified for post-clone add-ons). It consolidates the `usage-rules.md` files shipped by dependencies into `AGENTS.md` between managed comment markers ("Consolidates these rules into a target file with special markers like `<-- package-name-start -->` and `<-- package-name-end -->`"), and can also generate `.claude/skills/<skill>/SKILL.md` files.

Install after clone:

```
mix igniter.install usage_rules
```

Configuration is via a `:usage_rules` key in the `mix.exs` project config. The pre-1.0 CLI flags `--link-to-folder`/`--inline` were removed at **v0.2** in favor of config — the README states "v0.2 replaces CLI arguments with project config":

```elixir
def project do
  [
    app: :my_app,
    # ...
    usage_rules: [
      file: "AGENTS.md",
      usage_rules: [
        :usage_rules,          # documents the search_docs/docs tasks for agents
        :elixir,               # built-in Elixir rules
        :otp,                  # built-in OTP rules
        :phoenix,
        "phoenix:all",         # Phoenix's shipped sub-rules (elixir, html, ecto, liveview, …)
        ~r/^phoenix_/,
        :ecto,
        :ecto_sql,
        :req
      ]
    ]
  ]
end
```

**Decision: no hand-maintained language-gotchas section in AGENTS.md.** The built-in `:elixir` rules already cover the standard agent failure modes (no bracket indexing on lists, no `String.to_atom/1` on user input, predicate naming, block-return/rebinding semantics, Stream vs Enum, and more), and Phoenix ships its Phoenix.new-derived guidance (HEEx syntax, `to_form`, LiveView streams, Ecto preloads) as usage-rules sub-files. Duplicating any of this by hand would drift as dependencies upgrade and would spend the always-loaded context budget twice on the same rules; the managed section is the single source. At bootstrap, `mix usage_rules.sync --list` verifies which sub-rules the installed Phoenix version actually ships. If the inlined managed section grows large enough to threaten the 32 KiB Codex ceiling, individual packages switch to `{pkg, link: :markdown}` entries rather than trimming rules.

Sync is a bare invocation; the mix.exs config is the source of truth ("The config is the source of truth — packages present in the file but absent from config are automatically removed on each sync"):

```
mix usage_rules.sync
```

**Workflow decision:** `mix usage_rules.sync` runs after every dependency change, and the result is committed. usage_rules v1.2.x has **no built-in check/verify flag** (verified against the v1.2.7 task docs, the GitHub README, and the mix task; the only sync-related switch is the informational `--list`). CI therefore enforces currency by re-running the sync and failing on any diff (see the CI step in §10): `mix usage_rules.sync` followed by `git diff --exit-code AGENTS.md`. This is documented discipline, not a package feature; if a future version adds a `--check` mode, the CI step is simplified to use it (a revision trigger).

Two version-accurate documentation tasks are available to agents and referenced in AGENTS.md:

- `mix usage_rules.search_docs <query>` — searches HexDocs "with human-readable markdown output, designed for both humans and AI agents."
- `mix usage_rules.docs Module.fun` — looks up docs for a specific module/function at the installed version.

### 13.4 Tidewave (decided-in, dev-only MCP server)

Tidewave (tidewave-ai/tidewave_phoenix, `~> 0.9`; published by josevalim/Dashbit, ~1.66M all-time downloads and last updated July 2026 on Hex) is a mature, dev-only MCP server that exposes runtime introspection — code evaluation, log inspection, SQL queries over the dev database, and version-accurate documentation — to coding agents. Because it is a single dependency plus a single plug, it is **decided-in as a dev-only dependency** (not relegated to add-ons).

`mix.exs`:

```elixir
{:tidewave, "~> 0.9", only: :dev}
```

`lib/my_app_web/endpoint.ex`, immediately above the `if code_reloading? do` block (per Tidewave's official install docs):

```elixir
if Mix.env() == :dev do
  plug Tidewave
end

if code_reloading? do
  # ... existing code-reloading plugs ...
end
```

Tidewave runs on the app's own port; the MCP server is at `http://localhost:4000/tidewave/mcp` and — per Tidewave's docs — "does not require authentication, as it runs on your machine and accepts only local connections by default," so none is configured. Connect Claude Code with:

```
claude mcp add --transport http tidewave http://127.0.0.1:4000/tidewave/mcp
```

Tidewave is dev-only; agents cannot introspect production or staging through it.

### 13.5 CI bridge guard

A CI step fails the build if `CLAUDE.md` does not contain the literal line `@AGENTS.md`, guarding against an accidental deletion of the bridge. The exact step (already in the §10 test job):

```yaml
      - name: Verify CLAUDE.md bridge
        run: grep -qxF '@AGENTS.md' CLAUDE.md
```

`grep -qxF` matches the whole line (`-x`) literally (`-F`) and is quiet (`-q`), exiting non-zero if the line is absent.

### 13.6 usage_rules currency guard

Also in the §10 test job, the sync is re-run and any resulting diff fails the build, ensuring `AGENTS.md`'s managed dependency sections match the locked dependencies.

### 13.7 Canonical AGENTS.md and CONTRIBUTING.md content

Instruction content is split across two files. `AGENTS.md` carries only what an agent must hold in attention on every task: behavioral rules, project decisions it must not violate, and the usage_rules managed section, which supplies language, OTP, and framework rules synced from the installed dependencies. Reference material — setup commands, command variants, and operational detail — lives in `CONTRIBUTING.md`, which serves humans and agents alike; `AGENTS.md` points to its sections, and agents read them on demand. This keeps `AGENTS.md` far under the 32 KiB Codex ceiling and spends the always-loaded attention budget only on rules that change agent behavior.

Both files contain `my_app`/`MyApp` tokens and are rewritten by the rename task (§1). usage_rules maintains its managed section in `AGENTS.md` between its markers; the section is never hand-edited.

The ready-to-commit `AGENTS.md`:

````markdown
# AGENTS.md

Production-shaped Elixir + Phoenix LiveView application deployed to Fly.io.
Setup commands and operational reference live in CONTRIBUTING.md; read the
section referenced below before working in that area.

## Project overview

- Elixir 1.20+, Erlang/OTP 28, Phoenix 1.8 with LiveView, Ecto + PostgreSQL 18.
- Single web server: Bandit. HTTP client: `Req` (never `:httpoison`, `:tesla`, `:httpc`).
- Setup and everyday commands: CONTRIBUTING.md § Setup.

## Quality gate

- Run `mix precommit` when you are done with changes and fix everything it
  reports. Its steps are defined by the `precommit` alias in `mix.exs`.
- Dialyzer runs in CI only, not in `precommit`.

## Testing

- Reproduce a problem with the narrowest test first (`mix test path/to/test.exs:42`),
  then run `mix precommit`.
- Use the Ecto SQL Sandbox. A test may be `async: true` only when it does not share
  mutable global state; otherwise keep it synchronous.
- Use `Phoenix.LiveViewTest` and PhoenixTest. Assert against key element IDs you added
  in templates (`element/2`, `has_element?/2`); never assert against raw HTML strings.
- Command variants and the full test stack: CONTRIBUTING.md § Testing.

## Database changes

- Before making ANY schema or migration change, read
  CONTRIBUTING.md § Database & migrations. Blue-green deployment makes
  expand-contract mandatory; that section defines the required sequence,
  concurrent-index rules, and the release migrator.

## Security & secrets

- Never commit secrets. Runtime configuration comes from environment variables read
  in `config/runtime.exs` (`MY_APP_`-prefixed SNAKE_CASE).
- Both magic-link and password login are first-class. Login is required at
  confirmation as pre-stuffing defense — do not weaken this.
- Inbound webhook signature verification is manual by design (no `svix` dependency);
  read CONTRIBUTING.md § Inbound webhooks before touching it.
- Fields set programmatically (e.g. `user_id`) must NOT appear in `cast/3`; set them
  explicitly when building the struct.

## Elixir / Phoenix rules

- Language, OTP, Phoenix, Ecto, and package-specific rules are maintained in the
  usage_rules managed section at the bottom of this file. Consult them before
  writing code; they are synced from the installed dependency versions.

## Conventions & tools

- Make focused, imperative commits; never commit generated artifacts, `_build`,
  `deps`, or secrets.
- Re-verify tool and dependency versions at bootstrap; this file may lag reality.
- Tidewave MCP (dev) is available at `http://localhost:4000/tidewave/mcp` — use it to
  evaluate code, inspect logs, and query the dev database.
- Observability endpoints and metrics: CONTRIBUTING.md § Observability & health.

<!-- usage-rules-start -->
<!-- usage_rules maintains dependency usage rules between these markers.
     Do not edit by hand; run `mix usage_rules.sync`. -->
<!-- usage-rules-end -->
````

The ready-to-commit `CONTRIBUTING.md`:

````markdown
# CONTRIBUTING.md

Contributor reference for humans and coding agents. The always-loaded agent rules
live in AGENTS.md; this file holds the detail those rules point to.

## Setup

- Install and set up everything: `mix setup`
- Create/migrate/seed the database: `mix ecto.setup`
- Drop and recreate the database: `mix ecto.reset`
- Run the app: `mix phx.server` (or `iex -S mix phx.server`)
- Quality gate: `mix precommit` (steps defined by the alias in `mix.exs`).
  Dialyzer runs in CI; run `mix dialyzer` locally only when investigating a
  CI failure.

## Testing

- Run all tests: `mix test`
- Run one file: `mix test test/my_app_web/live/widget_live_test.exs`
- Run one test: `mix test test/my_app_web/live/widget_live_test.exs:42`
- Re-run only failures: `mix test --failed`
- Stack: ExUnit, Ecto SQL Sandbox, Mox, StreamData, `Phoenix.LiveViewTest`,
  PhoenixTest.

## Database & migrations

- Blue-green deployment runs old and new code against one database. Use
  expand-contract: ship an additive migration, roll out code, then ship a
  contracting migration later. Never change schema and dependent code in one step.
- Create indexes concurrently outside a transaction:
  `@disable_ddl_transaction true` and `@disable_migration_lock true`.
- Add CHECK constraints with `NOT VALID` first, then `VALIDATE CONSTRAINT` in a
  later migration.
- Set `lock_timeout` / `statement_timeout` for potentially slow DDL.
- Migrations run in prod via `MyApp.Release.migrate/0` (the Fly release command),
  never `mix ecto.migrate` on a prod box.

## Inbound webhooks

- Resend `email.received` events are metadata-only; full content, when needed, is
  fetched from the Receiving API using the event's email id.
- Signatures are verified manually with the Svix scheme: HMAC-SHA256 over
  `id.timestamp.body`, `whsec_`-stripped base64-decoded key, constant-time
  comparison, ±300s timestamp tolerance. The absence of a `svix` dependency is
  a deliberate decision — do not add one.
- Events are deduplicated on `svix-id` via the `webhook_events` table; handlers
  return 200 fast. Only the `svix-id` is persisted — email metadata is never
  stored in the database.
- After dedupe, `MyApp.Inbound` broadcasts the event metadata over
  `Phoenix.PubSub` on a per-sender topic (`inbound_emails:<normalized from>`).
  The `/inbox` LiveView subscribes for the logged-in user's address, backfills
  history from `GET /emails/receiving`, and keeps everything in process memory.
- `From`-based matching is spoofable; it demonstrates data flow and must never
  be used as an authentication or authorization signal.

## Observability & health

- `GET /healthz/live` — liveness, always 200, dependency-free.
- `GET /healthz/ready` — readiness from a periodic `SELECT 1` probe cached in
  `:persistent_term`.
- Prometheus metrics are served on private port 9091 and scraped by Fly; the
  port is never exposed as a public service.
- OpenTelemetry is wired for Phoenix, Bandit, and Ecto; `trace_id` appears in
  the JSON logs.
````

---

## Implementation order

1. Create from the GitHub template, clone, and run `mix my_app.rename --otp <otp> --module <Module>`.
2. `mix setup`.
3. `mix igniter.install usage_rules`, then `mix usage_rules.sync` (populates AGENTS.md's managed section).
4. Verify the CLAUDE.md bridge (`grep -qxF '@AGENTS.md' CLAUDE.md`).
5. Add the Tidewave dep and dev-endpoint plug; connect it in dev with `claude mcp add`.
6. Provision Fly (`fly launch` / `fly secrets`), configure blue-green + release migrator.
7. Run `mix precommit`; open the first PR through CI.

## Revision triggers

- **Claude Code ships native AGENTS.md discovery** → drop the CLAUDE.md bridge and its CI guard.
- **usage_rules gains a `--check`/verify mode** → replace the `git diff --exit-code` CI step with the native check.
- **usage_rules or tidewave major-version change** → re-verify config surface and endpoint wiring.
- **AGENTS.md standard gains a schema** → revisit whether headings must be normalized.
- **New Phoenix/LiveView CVE or a new LTS** → bump version floors and re-run `mix hex.audit`.

## Caveats

- Pre-1.0 dependencies (postgrex, req, tailwind wrapper, opentelemetry_bandit, igniter, tidewave, PhoenixTest) may make breaking changes on minor bumps; pin and re-verify.
- The Svix signature scheme should be re-verified against Resend's current docs before relying on it in production.
- Resend `email.received` is metadata-only; full content must be fetched from the Receiving API.
- The List Received Emails endpoint (`GET /emails/receiving`) is cursor-paginated; the inbox backfill filters by sender in-app. Re-verify at bootstrap whether the endpoint has grown server-side `from`/`to` filter params and use them if so.
- Inbox matching trusts the spoofable `From` header by design, as a data-flow demonstration only; never derive authentication, authorization, or account mutations from inbound email.
- The Ecto migration lock default (`:table_lock`) is a deliberate choice; advisory locking is opt-in.
- `fly.toml` schema drifts over time; re-verify check/service stanzas against current Fly docs.
- CVE floors: keep Phoenix ≥ 1.8.11 and LiveView ≥ 1.2.9, and run `mix hex.audit` in CI.
- Swoosh's first-party Resend adapter shipped in 1.20.0; do not float the floor below it.
- usage_rules' invocation surface changed across the pre-1.0 line (CLI flags removed at v0.2 in favor of `:usage_rules` mix.exs config); verify against the installed version.
- Claude Code's import max-depth is documented as four hops on the current canonical docs (one mirror says five); do not build import chains deeper than four.
- Third-party agent skills are executable instructions; review their content before adopting any.
- Codex silently truncates AGENTS.md at 32 KiB (`project_doc_max_bytes` default) — keep the file lean.

## Bootstrap checklist

- [ ] `mix my_app.rename` run; template task self-deleted.
- [ ] `LICENSE` copyright line updated (year + holder) for the new project.
- [ ] `mix setup` completes; `mix phx.server` boots.
- [ ] `mix precommit` passes locally.
- [ ] `mix usage_rules.sync` run; AGENTS.md managed section populated and committed.
- [ ] CLAUDE.md contains `@AGENTS.md`; CI bridge guard passes.
- [ ] Tidewave reachable in dev; `claude mcp add` succeeds.
- [ ] Agent smoke test: an agent can run `mix precommit` from AGENTS.md instructions alone; CONTRIBUTING.md sections referenced by AGENTS.md all exist.
- [ ] Inbox data-flow smoke test: send an email from a registered account's address to the inbound address; it appears live at `/inbox` and survives a remount via API backfill.
- [ ] Fly secrets set; blue-green deploy succeeds; readiness gate healthy.
