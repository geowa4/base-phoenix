defmodule MyApp.Inbound do
  @moduledoc """
  Inbound email fan-out and extension point. No email data is persisted.

  The webhook controller calls `record_event/2` (dedupe) and then
  `handle_event/1`, which normalizes the metadata and broadcasts it over
  `Phoenix.PubSub` on a per-sender topic. Future processing (Receiving API
  fetches, agent workflows, ...) belongs here.
  """

  alias MyApp.Inbound.WebhookEvent
  alias MyApp.Repo

  @pubsub MyApp.PubSub

  @doc """
  Records a webhook delivery by its `svix-id`. Returns `{:error, :duplicate}`
  when the delivery has already been seen.
  """
  @spec record_event(String.t(), String.t() | nil) ::
          {:ok, WebhookEvent.t()} | {:error, :duplicate}
  def record_event(svix_id, event_type) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(%{svix_id: svix_id, event_type: event_type})
    |> Repo.insert()
    |> case do
      {:ok, event} -> {:ok, event}
      {:error, _changeset} -> {:error, :duplicate}
    end
  end

  @doc "Subscribes the caller to inbound emails sent from `email`."
  def subscribe(email), do: Phoenix.PubSub.subscribe(@pubsub, topic_for(email))

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
      from: normalize(data["from"] || ""),
      to: data["to"] || [],
      subject: data["subject"],
      received_at: data["created_at"]
    }

    Phoenix.PubSub.broadcast(@pubsub, topic_for(meta.from), {:email_received, meta})
    :ok
  end

  def handle_event(_other), do: :ok
end
