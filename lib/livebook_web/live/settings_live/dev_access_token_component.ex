defmodule LivebookWeb.SettingsLive.DevAccessTokenComponent do
  use LivebookWeb, :live_component

  alias Livebook.Settings
  alias Livebook.Settings.DevAccessToken

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       changeset: Settings.change_dev_access_token(%DevAccessToken{}),
       plain_token: nil
     )}
  end

  @impl true
  def render(%{plain_token: nil} = assigns) do
    ~H"""
    <div class="flex flex-col space-y-5">
      <h3 class="text-2xl font-semibold text-gray-800">
        Create access token
      </h3>
      <p class="text-gray-700">
        Once a token exists, every request to the dev endpoints must
        include one in the <code>authorization</code> header.
      </p>
      <.form
        :let={f}
        id={"#{@id}-form"}
        for={@changeset}
        as={:dev_access_token}
        phx-submit="save"
        phx-change="validate"
        phx-target={@myself}
        autocomplete="off"
        spellcheck="false"
      >
        <div class="flex flex-col space-y-4">
          <.text_field
            field={f[:name]}
            label="Name"
            placeholder="VS Code"
            autofocus
          />
          <div class="flex space-x-2">
            <.button type="submit" phx-disable-with="Creating..." disabled={not @changeset.valid?}>
              Create
            </.button>
            <.button color="gray" outlined patch={@return_to}>
              Cancel
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={"#{@id}-created"} class="flex flex-col space-y-5">
      <h3 class="text-2xl font-semibold text-gray-800">
        Access token created
      </h3>
      <.message_box kind="warning">
        Make sure to copy the token now. For security reasons it is not
        stored and you won't be able to see it again.
      </.message_box>
      <.code_preview_with_title_and_copy
        title="Token"
        source_id={"#{@id}-value"}
        language="text"
        source={@plain_token}
      />
      <.code_preview_with_title_and_copy
        title="Example request"
        source_id={"#{@id}-example"}
        language="shell"
        source={example_request(@plain_token)}
      />
      <div>
        <.button patch={@return_to}>Done</.button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"dev_access_token" => attrs}, socket) do
    changeset =
      %DevAccessToken{}
      |> Settings.change_dev_access_token(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"dev_access_token" => attrs}, socket) do
    case Settings.create_dev_access_token(attrs) do
      {:ok, _token, plain_token} ->
        {:noreply, assign(socket, plain_token: plain_token)}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp example_request(plain_token) do
    """
    curl -X POST #{LivebookWeb.Endpoint.url()}#{~p"/dev/open"} \\
      -H "authorization: Bearer #{plain_token}" \\
      -H "content-type: application/json" \\
      -d '{"file": "/path/to/notebook.livemd"}'\
    """
  end
end
