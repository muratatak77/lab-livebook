defmodule LivebookWeb.SettingsLive.DevAccessTokensComponent do
  use LivebookWeb, :live_component

  alias Livebook.Settings.DevAccessToken

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col space-y-4">
      <.no_entries :if={@tokens == []}>
        No access tokens yet. Dev endpoints accept any request until you create one.
      </.no_entries>
      <div :if={@tokens != []}>
        <.table id="dev-access-tokens-table" rows={@tokens}>
          <:col :let={token} label="Name">{token.name}</:col>
          <:col :let={token} label="Token">
            <code class="text-sm">{DevAccessToken.masked(token)}</code>
          </:col>
          <:col :let={token} label="Created">
            {LivebookWeb.HTMLHelpers.format_datetime_relatively(token.inserted_at)} ago
          </:col>
          <:col :let={token} label="Last used">
            <%= if token.last_used_at do %>
              {LivebookWeb.HTMLHelpers.format_datetime_relatively(token.last_used_at)} ago
            <% else %>
              Never
            <% end %>
          </:col>
          <:action :let={token}>
            <span class="tooltip left" data-tooltip="Revoke">
              <.icon_button
                id={"dev-access-token-#{token.id}-delete"}
                type="button"
                aria-label="revoke token"
                phx-click={JS.push("delete_dev_access_token", value: %{id: token.id})}
              >
                <.remix_icon icon="delete-bin-6-line" />
              </.icon_button>
            </span>
          </:action>
        </.table>
      </div>
    </div>
    """
  end
end
