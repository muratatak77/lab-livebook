defmodule Livebook.Settings.DevAccessTokenTest do
  use ExUnit.Case, async: true

  alias Livebook.Settings.DevAccessToken

  describe "generate/0" do
    test "returns a prefixed, url-safe token" do
      token = DevAccessToken.generate()

      assert "lb_dev_" <> random = token
      assert byte_size(random) == 32
      assert random =~ ~r/^[A-Za-z0-9_-]+$/
    end
  end

  describe "hash/1" do
    test "returns a stable hex digest" do
      token = DevAccessToken.generate()

      assert DevAccessToken.hash(token) == DevAccessToken.hash(token)
      assert DevAccessToken.hash(token) =~ ~r/^[0-9a-f]{64}$/
      refute DevAccessToken.hash(token) == DevAccessToken.hash(token <> "x")
    end
  end

  test "masked/1 shows only the token suffix" do
    token = "lb_dev_" <> String.duplicate("a", 28) <> "wxyz"
    access_token = %DevAccessToken{token_hint: DevAccessToken.hint(token)}

    assert DevAccessToken.masked(access_token) == "lb_dev_…wxyz"
  end

  describe "changeset/2" do
    test "trims the name" do
      changeset = DevAccessToken.changeset(%DevAccessToken{}, %{name: "  CLI  "})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "CLI"
    end

    test "ignores fields other than the name" do
      changeset =
        DevAccessToken.changeset(%DevAccessToken{}, %{name: "CLI", token_hash: "forged"})

      assert Ecto.Changeset.get_change(changeset, :token_hash) == nil
    end

    test "requires a name" do
      refute DevAccessToken.changeset(%DevAccessToken{}, %{name: "   "}).valid?
    end
  end
end
