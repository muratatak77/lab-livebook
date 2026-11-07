defmodule LivebookWeb.SettingsLiveTest do
  use LivebookWeb.ConnCase, async: true
  @moduletag :tmp_dir

  import Phoenix.LiveViewTest
  import Livebook.TestHelpers

  alias Livebook.Settings

  describe "environment variables configuration" do
    test "list persisted environment variables", %{conn: conn} do
      insert_env_var(:env_var, name: "MY_ENVIRONMENT_VAR")
      assert conn |> get(~p"/settings") |> html_response(200) =~ "MY_ENVIRONMENT_VAR"
    end

    test "adds an environment variable", %{conn: conn} do
      attrs = params_for(:env_var)

      {:ok, view, html} = live(conn, ~p"/settings/env-var/new")

      assert html =~ "Add environment variable"
      refute html =~ attrs.name

      view
      |> element("#env-var-form")
      |> render_change(%{"env_var" => attrs})

      refute view
             |> element("#env-var-form .invalid-feedback")
             |> has_element?()

      view
      |> element("#env-var-form")
      |> render_submit(%{"env_var" => attrs})

      assert_patch(view, ~p"/settings")

      assert render(view) =~ attrs.name
    end

    test "updates an environment variable", %{conn: conn} do
      env_var = insert_env_var(:env_var, name: "UPDATE_ME")

      {:ok, view, html} = live(conn, ~p"/settings")

      assert html =~ env_var.name

      render_click(view, "edit_env_var", %{"env_var" => env_var.name})

      assert_patch(view, ~p"/settings/env-var/edit/#{env_var.name}")
      assert render(view) =~ "Edit environment variable"

      form = element(view, "#env-var-form")
      assert render(form) =~ env_var.value

      render_change(form, %{"env_var" => %{"value" => "123456"}})

      refute view
             |> element(".invalid-feedback")
             |> has_element?()

      render_submit(form, %{"env_var" => %{"value" => "123456"}})
      assert_patch(view, ~p"/settings")

      updated_env_var = Settings.fetch_env_var!(env_var.name)

      assert updated_env_var.name == env_var.name
      refute updated_env_var.value == env_var.value
    end

    test "deletes an environment variable", %{conn: conn} do
      env_var = insert_env_var(:env_var)
      {:ok, view, html} = live(conn, ~p"/settings")

      assert html =~ env_var.name

      view
      |> element("#env-var-#{env_var.name}-delete")
      |> render_click()

      render_confirm(view)

      refute view
             |> element("#env-vars")
             |> render() =~ env_var.name
    end
  end

  describe "dev access tokens" do
    setup do
      Settings.set_dev_endpoints_enabled(true)

      on_exit(fn ->
        Settings.set_dev_endpoints_enabled(false)

        for token <- Settings.fetch_dev_access_tokens() do
          Settings.delete_dev_access_token(token.id)
        end
      end)
    end

    test "are only configurable when dev endpoints are enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert has_element?(view, "#add-dev-access-token")

      view
      |> element(~s{form[phx-change="save"]}, "Control Livebook via local HTTP endpoints")
      |> render_change(%{"dev_endpoints_enabled" => "false"})

      refute has_element?(view, "#add-dev-access-token")
    end

    test "creates an access token and reveals it once", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/dev-access-token/new")

      assert html =~ "Create access token"

      assert view
             |> element("#dev-access-token-form")
             |> render_change(%{"dev_access_token" => %{"name" => ""}}) =~ "can&#39;t be blank"

      view
      |> element("#dev-access-token-form")
      |> render_submit(%{"dev_access_token" => %{"name" => "Neovim"}})

      assert [token] = Settings.fetch_dev_access_tokens()
      assert token.name == "Neovim"

      plain_token =
        view
        |> element("#dev-access-token-value")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()
        |> String.trim()

      assert {:ok, _} = Settings.verify_dev_access_token(plain_token)
      html = render(view)
      assert html =~ "authorization: Bearer #{plain_token}"

      # The example uses the bound address, without the access token query
      base_url = %{LivebookWeb.Endpoint.access_struct_url() | path: nil, query: nil}
      assert html =~ "curl -X POST #{base_url}/dev/open "
      refute html =~ "/dev/open?token="

      view
      |> element("#dev-access-token-created a", "Done")
      |> render_click()

      assert_patch(view, ~p"/settings")

      html = view |> element("#dev-access-tokens") |> render()
      assert html =~ "Neovim"
      assert html =~ Settings.DevAccessToken.masked(token)
      refute html =~ plain_token
    end

    test "shows an error when the name is already taken", %{conn: conn} do
      insert_dev_access_token(name: "Zed")

      {:ok, view, _html} = live(conn, ~p"/settings/dev-access-token/new")

      assert view
             |> element("#dev-access-token-form")
             |> render_change(%{"dev_access_token" => %{"name" => "zed"}}) =~
               "has already been taken"

      assert has_element?(view, "#dev-access-token-form button[type=submit][disabled]")

      assert view
             |> element("#dev-access-token-form")
             |> render_submit(%{"dev_access_token" => %{"name" => "Zed"}}) =~
               "has already been taken"

      assert [_] = Settings.fetch_dev_access_tokens()
    end

    test "revokes an access token", %{conn: conn} do
      {token, _} = insert_dev_access_token(name: "Emacs")

      {:ok, view, html} = live(conn, ~p"/settings")
      assert html =~ "Emacs"

      view
      |> element("#dev-access-token-#{token.id}-delete")
      |> render_click()

      render_confirm(view)

      assert Settings.fetch_dev_access_tokens() == []
      refute view |> element("#dev-access-tokens") |> render() =~ "Emacs"
    end
  end

  describe "autosaving" do
    # Autosaving can only be disabled by directly changing storage,
    # which we do for tests. That said, it is a valid setting, so we
    # have a UI to enable autosaving back, just in case someone boots
    # Livebook with such storage.
    test "can be enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#enable-autosave")
      |> render_click()

      view
      |> element("#cancel-autosave")
      |> render_click()
    end
  end
end
