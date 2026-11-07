defmodule Livebook.Settings do
  # Keeps all Livebook settings that are backed by storage.

  import Ecto.Changeset, only: [apply_action: 2]

  alias Livebook.FileSystem
  alias Livebook.Storage
  alias Livebook.Settings.EnvVar
  alias Livebook.Settings.DevAccessToken

  @doc """
  Returns the current autosave path.
  """
  @spec autosave_path() :: String.t() | nil
  def autosave_path() do
    case Storage.fetch_key(:settings, "global", :autosave_path) do
      {:ok, value} -> value
      :error -> default_autosave_path()
    end
  end

  @doc """
  Returns the default autosave path.
  """
  @spec default_autosave_path() :: String.t()
  def default_autosave_path() do
    Path.join(Livebook.Config.data_path(), "autosaved")
  end

  @doc """
  Sets the current autosave path.
  """
  @spec set_autosave_path(String.t()) :: :ok
  def set_autosave_path(autosave_path) do
    Storage.insert(:settings, "global", autosave_path: autosave_path)
  end

  @doc """
  Restores the default autosave path.
  """
  @spec reset_autosave_path() :: :ok
  def reset_autosave_path() do
    Storage.delete_key(:settings, "global", :autosave_path)
  end

  @doc """
  Returns whether the update check is enabled.
  """
  @spec update_check_enabled?() :: boolean()
  def update_check_enabled?() do
    case Storage.fetch_key(:settings, "global", :update_check_enabled) do
      {:ok, value} -> value
      :error -> true
    end
  end

  @doc """
  Sets whether the update check is enabled.
  """
  @spec set_update_check_enabled(boolean()) :: :ok
  def set_update_check_enabled(enabled) do
    Storage.insert(:settings, "global", update_check_enabled: enabled)
  end

  @doc """
  Returns whether the dev endpoints are enabled.
  """
  @spec dev_endpoints_enabled?() :: boolean()
  def dev_endpoints_enabled?() do
    case Storage.fetch_key(:settings, "global", :dev_endpoints_enabled) do
      {:ok, value} -> value
      :error -> false
    end
  end

  @doc """
  Sets whether the dev endpoints are enabled.
  """
  @spec set_dev_endpoints_enabled(boolean()) :: :ok
  def set_dev_endpoints_enabled(enabled) do
    Storage.insert(:settings, "global", dev_endpoints_enabled: enabled)
  end

  @doc """
  Returns all dev endpoint access tokens, oldest first.
  """
  @spec fetch_dev_access_tokens() :: list(DevAccessToken.t())
  def fetch_dev_access_tokens() do
    for fields <- Storage.all(:dev_access_tokens) do
      struct!(DevAccessToken, fields)
    end
    |> Enum.sort_by(& &1.inserted_at, DateTime)
  end

  @doc """
  Returns whether requests to the dev endpoints must include an access
  token.

  Tokens are required as soon as at least one has been created.
  """
  @spec dev_access_tokens_required?() :: boolean()
  def dev_access_tokens_required?() do
    Storage.all(:dev_access_tokens) != []
  end

  @doc """
  Creates a new dev endpoint access token.

  On success, returns the stored token together with the plain token
  value. The plain value is not persisted, so this is the only time
  it is available.
  """
  @spec create_dev_access_token(map()) ::
          {:ok, DevAccessToken.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_dev_access_token(attrs) do
    changeset = change_dev_access_token(%DevAccessToken{}, attrs)

    with {:ok, token} <- apply_action(changeset, :insert) do
      plain_token = DevAccessToken.generate()

      token = %{
        token
        | id: Livebook.Utils.random_short_id(),
          token_hash: DevAccessToken.hash(plain_token),
          token_hint: DevAccessToken.hint(plain_token),
          inserted_at: DateTime.utc_now()
      }

      :ok = save_dev_access_token(token)
      broadcast_settings_change({:dev_access_token_created, token})

      {:ok, token, plain_token}
    end
  end

  defp validate_dev_access_token_name_unique(changeset) do
    name = Ecto.Changeset.get_field(changeset, :name)

    if name && Enum.any?(fetch_dev_access_tokens(), &name_equal?(&1.name, name)) do
      Ecto.Changeset.add_error(changeset, :name, "has already been taken")
    else
      changeset
    end
  end

  defp name_equal?(left, right), do: String.downcase(left) == String.downcase(right)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking access token changes.

  Includes the name uniqueness check, so forms can report a taken
  name before submitting.
  """
  @spec change_dev_access_token(DevAccessToken.t(), map()) :: Ecto.Changeset.t()
  def change_dev_access_token(%DevAccessToken{} = token, attrs \\ %{}) do
    token
    |> DevAccessToken.changeset(attrs)
    |> validate_dev_access_token_name_unique()
  end

  @doc """
  Revokes the dev endpoint access token with the given id.

  Does nothing if the token does not exist.
  """
  @spec delete_dev_access_token(String.t()) :: :ok
  def delete_dev_access_token(id) do
    with {:ok, fields} <- Storage.fetch(:dev_access_tokens, id) do
      :ok = Storage.delete(:dev_access_tokens, id)
      broadcast_settings_change({:dev_access_token_deleted, struct!(DevAccessToken, fields)})
    end

    :ok
  end

  # We don't need precise usage information, so we avoid writing the
  # storage file on every single request
  @last_used_at_resolution_s 60

  @doc """
  Looks up the access token matching the given plain token.

  On success, the token usage time is recorded.
  """
  @spec verify_dev_access_token(String.t()) :: {:ok, DevAccessToken.t()} | :error
  def verify_dev_access_token(plain_token) when is_binary(plain_token) do
    hash = DevAccessToken.hash(plain_token)

    token =
      Enum.find(fetch_dev_access_tokens(), fn token ->
        Plug.Crypto.secure_compare(token.token_hash, hash)
      end)

    if token do
      touch_dev_access_token(token)
    else
      :error
    end
  end

  defp touch_dev_access_token(token) do
    now = DateTime.utc_now(:second)

    if token.last_used_at == nil or
         DateTime.diff(now, token.last_used_at) >= @last_used_at_resolution_s do
      # The token may have been revoked since we read it, in which case
      # we must not recreate it
      case Storage.update(:dev_access_tokens, token.id, last_used_at: now) do
        :ok ->
          token = %{token | last_used_at: now}
          broadcast_settings_change({:dev_access_token_used, token})
          {:ok, token}

        :error ->
          :error
      end
    else
      {:ok, token}
    end
  end

  defp save_dev_access_token(token) do
    attributes = token |> Map.from_struct() |> Map.delete(:id) |> Map.to_list()
    Storage.insert(:dev_access_tokens, token.id, attributes)
  end

  @doc """
  Gets a list of environment variables from storage.
  """
  @spec fetch_env_vars() :: list(EnvVar.t())
  def fetch_env_vars do
    for fields <- Storage.all(:env_vars) do
      struct!(EnvVar, Map.delete(fields, :id))
    end
  end

  @doc """
  Gets one environment variable from storage.

  Raises `RuntimeError` if the environment variable does not exist.
  """
  @spec fetch_env_var!(String.t()) :: EnvVar.t()
  def fetch_env_var!(id) do
    fields = Storage.fetch!(:env_vars, id)
    struct!(EnvVar, Map.delete(fields, :id))
  end

  @doc """
  Checks if environment variable already exists.
  """
  @spec env_var_exists?(String.t()) :: boolean()
  def env_var_exists?(id) do
    Storage.fetch(:env_vars, id) != :error
  end

  @doc """
  Sets the given environment variable.

  With success, notifies interested processes about environment variable
  data change. Otherwise, it will return an error tuple with changeset.
  """
  @spec set_env_var(EnvVar.t(), map()) :: {:ok, EnvVar.t()} | {:error, Ecto.Changeset.t()}
  def set_env_var(%EnvVar{} = env_var \\ %EnvVar{}, attrs) do
    changeset = EnvVar.changeset(env_var, attrs)

    with {:ok, env_var} <- apply_action(changeset, :insert) do
      {:ok, save_env_var(env_var)}
    end
  end

  defp save_env_var(env_var) do
    attributes = env_var |> Map.from_struct() |> Map.to_list()
    :ok = Storage.insert(:env_vars, env_var.name, attributes)
    :ok = broadcast_env_vars_change({:env_var_set, env_var})
    env_var
  end

  @doc """
  Unsets an environment variable from given id.

  With success, notifies interested processes about environment variable
  deletion. Otherwise, it does nothing.
  """
  @spec unset_env_var(String.t()) :: :ok
  def unset_env_var(id) do
    if env_var_exists?(id) do
      env_var = fetch_env_var!(id)
      Storage.delete(:env_vars, id)
      broadcast_env_vars_change({:env_var_unset, env_var})
    end

    :ok
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking environment variable changes.
  """
  @spec change_env_var(EnvVar.t(), map()) :: Ecto.Changeset.t()
  def change_env_var(%EnvVar{} = env_var, attrs \\ %{}) do
    EnvVar.changeset(env_var, attrs)
  end

  @doc """
  Subscribes to updates in settings information.

  ## Messages

    * `{:env_var_set, env_var}`
    * `{:env_var_unset, env_var}`
    * `{:dev_access_token_created, token}`
    * `{:dev_access_token_deleted, token}`
    * `{:dev_access_token_used, token}`

  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Livebook.PubSub, "settings")
  end

  @doc """
  Unsubscribes from `subscribe/0`.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(Livebook.PubSub, "settings")
  end

  # Notifies interested processes about environment variables data change.
  #
  # Broadcasts given message under the `"settings"` topic.
  defp broadcast_env_vars_change(message) do
    broadcast_settings_change(message)
  end

  defp broadcast_settings_change(message) do
    Phoenix.PubSub.broadcast(Livebook.PubSub, "settings", message)
  end

  @doc """
  Sets default directory.
  """
  @spec set_default_dir(FileSystem.File.t()) :: :ok
  def set_default_dir(file) do
    Storage.insert(:settings, "global",
      default_dir: %{
        file_system_id: file.file_system_id,
        file_system_type: Livebook.FileSystems.module_to_type(file.file_system_module),
        path: file.path
      }
    )
  end

  @doc """
  Gets default directory.
  """
  @spec default_dir() :: FileSystem.File.t()
  def default_dir() do
    with {:ok, %{file_system_id: file_system_id, file_system_type: file_system_type, path: path}} <-
           Storage.fetch_key(:settings, "global", :default_dir) do
      %FileSystem.File{
        file_system_id: file_system_id,
        file_system_module: Livebook.FileSystems.type_to_module(file_system_type),
        path: path,
        origin_pid: self()
      }
    else
      _ -> FileSystem.File.new(Livebook.Config.local_file_system())
    end
  end

  @doc """
  Gets default directory based on given hub.
  """
  @spec default_dir(Livebook.Hubs.Provider.t()) :: FileSystem.File.t()
  def default_dir(hub) do
    file_systems = Livebook.Hubs.get_file_systems(hub)
    file = default_dir()

    if Enum.any?(file_systems, &(&1.id == file.file_system_id)) do
      file
    else
      Livebook.Config.local_file_system_home()
    end
  end
end
