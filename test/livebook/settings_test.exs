defmodule Livebook.SettingsTest do
  use Livebook.DataCase

  alias Livebook.Settings

  test "fetch_env_vars/0 returns a list of persisted environment variables" do
    env_var = insert_env_var(:env_var)
    assert env_var in Settings.fetch_env_vars()

    Settings.unset_env_var(env_var.name)
    refute env_var in Settings.fetch_env_vars()
  end

  test "fetch_env_var!/1 returns one persisted environment variable" do
    %{name: name} = build(:env_var)

    assert_raise Livebook.Storage.NotFoundError,
                 ~s/could not find entry in \"env_vars\" with ID "#{name}"/,
                 fn ->
                   Settings.fetch_env_var!(name)
                 end

    env_var = insert_env_var(:env_var, name: name)
    assert Settings.fetch_env_var!(name) == env_var

    Settings.unset_env_var(name)
  end

  test "env_var_exists?/1" do
    %{name: name} = build(:env_var)

    refute Settings.env_var_exists?(name)
    insert_env_var(:env_var, name: name)
    assert Settings.env_var_exists?(name)

    Settings.unset_env_var(name)
  end

  describe "set_env_var/1" do
    test "creates an environment variable" do
      attrs = params_for(:env_var)
      assert {:ok, env_var} = Settings.set_env_var(attrs)

      assert attrs.name == env_var.name
      assert attrs.value == env_var.value

      Settings.unset_env_var(env_var.name)
    end

    test "updates an environment variable" do
      env_var = insert_env_var(:env_var)
      attrs = %{value: "FOO"}
      assert {:ok, updated_env_var} = Settings.set_env_var(env_var, attrs)

      assert env_var.name == updated_env_var.name
      assert updated_env_var.value == attrs.value

      Settings.unset_env_var(env_var.name)
    end

    test "returns changeset error" do
      attrs = params_for(:env_var, name: nil)
      assert {:error, changeset} = Settings.set_env_var(attrs)
      assert "can't be blank" in errors_on(changeset).name

      assert {:error, changeset} = Settings.set_env_var(%{attrs | name: "LB_FOO"})
      assert "cannot start with the LB_ prefix" in errors_on(changeset).name
    end
  end

  describe "dev access tokens" do
    setup do
      on_exit(fn ->
        for token <- Settings.fetch_dev_access_tokens() do
          Settings.delete_dev_access_token(token.id)
        end
      end)
    end

    test "create_dev_access_token/1 stores only the token digest" do
      refute Settings.dev_access_tokens_required?()

      assert {:ok, token, plain_token} = Settings.create_dev_access_token(%{name: " VS Code "})

      assert "lb_dev_" <> _ = plain_token
      assert token.name == "VS Code"
      assert token.token_hint == String.slice(plain_token, -4, 4)
      assert token.token_hash == Settings.DevAccessToken.hash(plain_token)
      assert %DateTime{} = token.inserted_at
      assert token.last_used_at == nil

      assert Settings.fetch_dev_access_tokens() == [token]
      assert Settings.dev_access_tokens_required?()

      stored = Livebook.Storage.fetch!(:dev_access_tokens, token.id)
      refute plain_token in Map.values(stored)
    end

    test "create_dev_access_token/1 generates a distinct token every time" do
      {:ok, _, plain_token1} = Settings.create_dev_access_token(%{name: "First"})
      {:ok, _, plain_token2} = Settings.create_dev_access_token(%{name: "Second"})

      assert plain_token1 != plain_token2

      assert [%{name: "First"}, %{name: "Second"}] = Settings.fetch_dev_access_tokens()
    end

    test "create_dev_access_token/1 returns changeset error" do
      assert {:error, changeset} = Settings.create_dev_access_token(%{name: ""})
      assert "can't be blank" in errors_on(changeset).name

      long_name = String.duplicate("a", 65)
      assert {:error, changeset} = Settings.create_dev_access_token(%{name: long_name})
      assert "should be at most 64 character(s)" in errors_on(changeset).name

      {:ok, _, _} = Settings.create_dev_access_token(%{name: "CLI"})
      assert {:error, changeset} = Settings.create_dev_access_token(%{name: "cli"})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "verify_dev_access_token/1 matches the plain token and records usage" do
      {:ok, token, plain_token} = Settings.create_dev_access_token(%{name: "CLI"})

      assert :error = Settings.verify_dev_access_token("lb_dev_invalid")
      assert :error = Settings.verify_dev_access_token(token.token_hash)

      assert {:ok, %{id: id, last_used_at: %DateTime{} = last_used_at}} =
               Settings.verify_dev_access_token(plain_token)

      assert id == token.id
      assert [%{last_used_at: ^last_used_at}] = Settings.fetch_dev_access_tokens()
    end

    test "verify_dev_access_token/1 does not update usage more than once a minute" do
      {:ok, token, plain_token} = Settings.create_dev_access_token(%{name: "CLI"})

      recently = DateTime.add(DateTime.utc_now(:second), -10)
      Livebook.Storage.insert(:dev_access_tokens, token.id, last_used_at: recently)

      assert {:ok, %{last_used_at: ^recently}} = Settings.verify_dev_access_token(plain_token)

      long_ago = DateTime.add(DateTime.utc_now(:second), -120)
      Livebook.Storage.insert(:dev_access_tokens, token.id, last_used_at: long_ago)

      assert {:ok, %{last_used_at: last_used_at}} = Settings.verify_dev_access_token(plain_token)
      assert DateTime.after?(last_used_at, long_ago)
    end

    test "delete_dev_access_token/1 revokes the token and notifies subscribers" do
      Settings.subscribe()

      {:ok, token, plain_token} = Settings.create_dev_access_token(%{name: "CLI"})
      assert_receive {:dev_access_token_created, ^token}

      assert :ok = Settings.delete_dev_access_token(token.id)
      assert_receive {:dev_access_token_deleted, %{id: id}}
      assert id == token.id

      assert Settings.fetch_dev_access_tokens() == []
      assert :error = Settings.verify_dev_access_token(plain_token)

      # Deleting a missing token is a no-op
      assert :ok = Settings.delete_dev_access_token(token.id)
      refute_receive {:dev_access_token_deleted, _}
    end
  end
end
