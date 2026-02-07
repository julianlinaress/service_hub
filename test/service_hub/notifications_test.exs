defmodule ServiceHub.NotificationsTest do
  use ServiceHub.DataCase

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.TelegramAccount
  alias ServiceHub.Notifications.TelegramDestination
  alias ServiceHub.Accounts

  defmodule TelegramHTTPStub do
    def request(method: :get, url: url) do
      response = Process.get(:telegram_http_responses, %{})[url]

      case response do
        nil -> {:error, :not_stubbed}
        body -> {:ok, body}
      end
    end
  end

  describe "notification_channels" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "test@example.com", password: "password123password123"})

      scope = %ServiceHub.Accounts.Scope{user: user}
      %{scope: scope, user: user}
    end

    test "list_channels/1 returns all channels for user", %{scope: scope} do
      channel = channel_fixture(scope)
      assert Enum.map(Notifications.list_channels(scope), & &1.id) == [channel.id]
    end

    test "get_channel!/2 returns the channel with given id", %{scope: scope} do
      channel = channel_fixture(scope)
      assert Notifications.get_channel!(scope, channel.id).id == channel.id
    end

    test "create_channel/2 with valid data creates a channel", %{scope: scope} do
      valid_attrs = %{
        name: "Test Telegram",
        provider: "telegram",
        config: %{
          "token" => "123456:ABC-DEF",
          "chat_ref" => "-1001234567890"
        },
        enabled: true
      }

      assert {:ok, %NotificationChannel{} = channel} =
               Notifications.create_channel(scope, valid_attrs)

      assert channel.name == "Test Telegram"
      assert channel.provider == "telegram"
      assert channel.enabled == true
      assert channel.telegram_account_id
      assert channel.telegram_destination_id
    end

    test "create_channel/2 reuses telegram account and stores destination reference", %{
      scope: scope
    } do
      attrs_1 = %{
        name: "Primary",
        provider: "telegram",
        config: %{"token" => "123456:ABC-DEF", "chat_ref" => "@alerts"}
      }

      attrs_2 = %{
        name: "Secondary",
        provider: "telegram",
        config: %{"token" => "123456:ABC-DEF", "chat_ref" => "-100999"}
      }

      assert {:ok, channel_1} = Notifications.create_channel(scope, attrs_1)
      assert {:ok, channel_2} = Notifications.create_channel(scope, attrs_2)

      assert channel_1.telegram_account_id == channel_2.telegram_account_id
      assert channel_1.telegram_destination_id != channel_2.telegram_destination_id

      assert Repo.aggregate(TelegramAccount, :count) == 1
      assert Repo.aggregate(TelegramDestination, :count) == 2
    end

    test "create_channel/2 with invalid data returns error changeset", %{scope: scope} do
      invalid_attrs = %{name: nil, provider: nil, config: %{}}
      assert {:error, %Ecto.Changeset{}} = Notifications.create_channel(scope, invalid_attrs)
    end

    test "create_channel/2 validates telegram config", %{scope: scope} do
      invalid_attrs = %{
        name: "Test",
        provider: "telegram",
        config: %{"token" => "only-token"}
      }

      assert {:error, changeset} = Notifications.create_channel(scope, invalid_attrs)

      assert "must include token and chat_ref for Telegram, or linked telegram_account/telegram_destination" in errors_on(
               changeset
             ).config
    end

    test "create_channel/2 validates slack config", %{scope: scope} do
      invalid_attrs = %{
        name: "Test",
        provider: "slack",
        config: %{}
      }

      assert {:error, changeset} = Notifications.create_channel(scope, invalid_attrs)
      assert "must include webhook_url for Slack" in errors_on(changeset).config
    end

    test "update_channel/3 with valid data updates the channel", %{scope: scope} do
      channel = channel_fixture(scope)
      update_attrs = %{name: "Updated Name", enabled: false}

      assert {:ok, %NotificationChannel{} = channel} =
               Notifications.update_channel(scope, channel, update_attrs)

      assert channel.name == "Updated Name"
      assert channel.enabled == false
    end

    test "delete_channel/2 deletes the channel", %{scope: scope} do
      channel = channel_fixture(scope)
      assert {:ok, %NotificationChannel{}} = Notifications.delete_channel(scope, channel)
      assert_raise Ecto.NoResultsError, fn -> Notifications.get_channel!(scope, channel.id) end
    end

    test "change_channel/2 returns a channel changeset", %{scope: scope} do
      channel = channel_fixture(scope)
      assert %Ecto.Changeset{} = Notifications.change_channel(scope, channel)
    end

    test "create_channel/2 allows linked telegram account and destination", %{
      scope: scope,
      user: user
    } do
      account =
        Repo.insert!(%TelegramAccount{user_id: user.id, name: "Bot", bot_token: "123456:ABC-DEF"})

      destination =
        Repo.insert!(%TelegramDestination{telegram_account_id: account.id, chat_ref: "@alerts"})

      attrs = %{
        name: "Linked Telegram",
        provider: "telegram",
        telegram_account_id: account.id,
        telegram_destination_id: destination.id,
        config: %{"parse_mode" => "HTML"}
      }

      assert {:ok, channel} = Notifications.create_channel(scope, attrs)
      assert channel.telegram_account_id == account.id
      assert channel.telegram_destination_id == destination.id
    end
  end

  describe "telegram discovery" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{
          email: "telegram@example.com",
          password: "password123password123"
        })

      scope = %ServiceHub.Accounts.Scope{user: user}

      previous_client = Application.get_env(:service_hub, :telegram_http_client)
      Application.put_env(:service_hub, :telegram_http_client, TelegramHTTPStub)

      on_exit(fn ->
        if previous_client do
          Application.put_env(:service_hub, :telegram_http_client, previous_client)
        else
          Application.delete_env(:service_hub, :telegram_http_client)
        end
      end)

      %{scope: scope, user: user}
    end

    test "discover_telegram_destinations/2 creates account and destinations from updates", %{
      scope: scope
    } do
      token = "987654:XYZ-DEF"

      Process.put(:telegram_http_responses, %{
        "https://api.telegram.org/bot#{token}/getMe" => %{
          status: 200,
          body: %{"ok" => true, "result" => %{"id" => 1}}
        },
        "https://api.telegram.org/bot#{token}/getUpdates" => %{
          status: 200,
          body: %{
            "ok" => true,
            "result" => [
              %{"message" => %{"chat" => %{"id" => -1001, "title" => "Ops", "type" => "group"}}},
              %{
                "channel_post" => %{
                  "chat" => %{"id" => -2002, "username" => "release_alerts", "type" => "channel"}
                }
              }
            ]
          }
        }
      })

      params = %{"provider" => "telegram", "config" => %{"token" => token}}

      assert {:ok, account, destinations} =
               Notifications.discover_telegram_destinations(scope, params)

      assert account.bot_token == token
      assert Enum.any?(destinations, &(&1.chat_ref == "-1001"))
      assert Enum.any?(destinations, &(&1.chat_ref == "@release_alerts"))
    end

    test "discover_telegram_destinations/2 supports existing account selection", %{
      scope: scope,
      user: user
    } do
      token = "111111:AAA-BBB"

      account =
        Repo.insert!(%TelegramAccount{user_id: user.id, name: "Existing", bot_token: token})

      Process.put(:telegram_http_responses, %{
        "https://api.telegram.org/bot#{token}/getMe" => %{
          status: 200,
          body: %{"ok" => true, "result" => %{"id" => 2}}
        },
        "https://api.telegram.org/bot#{token}/getUpdates" => %{
          status: 200,
          body: %{"ok" => true, "result" => []}
        }
      })

      assert {:ok, ^account, []} =
               Notifications.discover_telegram_destinations(scope, %{
                 "provider" => "telegram",
                 "telegram_account_id" => to_string(account.id),
                 "config" => %{}
               })
    end
  end

  # Test Fixtures

  defp channel_fixture(scope, attrs \\ %{}) do
    default_attrs = %{
      name: "Test Channel",
      provider: "telegram",
      config: %{
        "token" => "123456:ABC-DEF",
        "chat_ref" => "-1001234567890"
      },
      enabled: true
    }

    {:ok, channel} =
      attrs
      |> Enum.into(default_attrs)
      |> then(&Notifications.create_channel(scope, &1))

    channel
  end
end
