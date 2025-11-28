defmodule ServiceHub.Providers.AuthRegistry do
  @moduledoc """
  Registry of supported auth types.
  """

  @registry %{
    "token" => %{
      key: "token",
      name: "Auth token",
      required_fields: %{
        "token" => %{
          "label" => "Access token",
          "type" => "password"
        }
      }
    }
  }

  def list_options do
    @registry
    |> Map.values()
    |> Enum.map(fn %{name: name, key: key} -> {name, key} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def fetch(key) when is_binary(key) do
    case Map.fetch(@registry, key) do
      {:ok, spec} -> {:ok, spec}
      :error -> :error
    end
  end

  def fetch(_), do: :error
end
