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
    },
    "github_pat" => %{
      key: "github_pat",
      name: "GitHub personal access token",
      required_fields: %{
        "token" => %{
          "label" => "GitHub token (classic or fine-grained)",
          "type" => "password"
        }
      }
    },
    "github_app" => %{
      key: "github_app",
      name: "GitHub App installation",
      required_fields: %{
        "app_id" => %{"label" => "App ID", "type" => "text"},
        "installation_id" => %{"label" => "Installation ID", "type" => "text"},
        "private_key" => %{
          "label" => "Private key (PEM)",
          "type" => "textarea"
        }
      }
    },
    "github_oauth" => %{
      key: "github_oauth",
      name: "GitHub OAuth (3-legged)",
      required_fields: %{
        "client_id" => %{"label" => "Client ID", "type" => "text"},
        "client_secret" => %{"label" => "Client secret", "type" => "password"},
        "scope" => %{"label" => "Scopes (comma or space separated)", "type" => "text"}
      }
    },
    "oauth" => %{
      key: "oauth",
      name: "Generic OAuth",
      required_fields: %{
        "client_id" => %{"label" => "Client ID", "type" => "text"},
        "client_secret" => %{"label" => "Client secret", "type" => "password"},
        "scope" => %{"label" => "Scopes", "type" => "text"}
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
