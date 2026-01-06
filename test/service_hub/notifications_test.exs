defmodule ServiceHub.NotificationsTest do
  use ServiceHub.DataCase

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Accounts

  describe "notification_channels" do
    setup do
      {:ok, user} = Accounts.register_user(%{email: "test@example.com", password: "password123password123"})
      scope = %ServiceHub.Accounts.Scope{user: user}
      %{scope: scope, user: user}
    end

    test "list_channels/1 returns all channels for user", %{scope: scope} do
      channel = channel_fixture(scope)
      assert Notifications.list_channels(scope) == [channel]
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
          "chat_id" => "-1001234567890"
        },
        enabled: true
      }

      assert {:ok, %NotificationChannel{} = channel} = Notifications.create_channel(scope, valid_attrs)
      assert channel.name == "Test Telegram"
      assert channel.provider == "telegram"
      assert channel.enabled == true
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
      assert "must include token and chat_id for Telegram" in errors_on(changeset).config
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
  end

  # Test Fixtures

  defp channel_fixture(scope, attrs \\ %{}) do
    default_attrs = %{
      name: "Test Channel",
      provider: "telegram",
      config: %{
        "token" => "123456:ABC-DEF",
        "chat_id" => "-1001234567890"
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
