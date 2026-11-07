defmodule Livebook.Settings.DevAccessToken do
  # An access token used to authenticate requests to the dev endpoints.
  #
  # We never store the token itself, only its SHA-256 digest, so the
  # plain token is only available right after creation. In addition
  # we keep the last few characters, so the user can tell tokens apart
  # in the settings page.

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          token_hash: String.t() | nil,
          token_hint: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil
        }

  @prefix "lb_dev_"
  @hint_length 4

  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :name, :string
    field :token_hash, :string
    field :token_hint, :string
    field :inserted_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime
  end

  @doc false
  def changeset(token, attrs \\ %{}) do
    token
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 32)
  end

  @doc """
  Generates a new plain token.
  """
  @spec generate() :: String.t()
  def generate() do
    @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  end

  @doc """
  Returns the digest under which the given plain token is stored.
  """
  @spec hash(String.t()) :: String.t()
  def hash(token) when is_binary(token) do
    :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
  end

  @doc """
  Returns the suffix of the given plain token that is safe to display.
  """
  @spec hint(String.t()) :: String.t()
  def hint(token) when is_binary(token) do
    String.slice(token, -@hint_length, @hint_length)
  end

  @doc """
  Returns a masked representation of the token, for display purposes.
  """
  @spec masked(t()) :: String.t()
  def masked(%__MODULE__{token_hint: hint}) do
    @prefix <> "…" <> hint
  end
end
