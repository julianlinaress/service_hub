defmodule ServiceHub.Notifications.TelegramConnectionsTest do
  use ServiceHub.DataCase, async: true

  import ServiceHub.AccountsFixtures

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.TelegramConnection
  alias ServiceHub.Notifications.TelegramConnections

  setup do
    user = user_fixture()
    scope = Scope.for_user(user)
    %{scope: scope}
  end

  describe "verify_widget_payload/1" do
    test "returns error for tampered hash" do
      assert {:error, :invalid_signature} =
               TelegramConnections.verify_widget_payload(%{
                 "id" => "123",
                 "first_name" => "Test",
                 "hash" => "deadbeef"
               })
    end
  end

  describe "upsert_connection/2" do
    test "creates a connection", %{scope: scope} do
      attrs = %{
        "telegram_id" => "12345",
        "first_name" => "Alice",
        "connected_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:ok, conn} = TelegramConnections.upsert_connection(scope, attrs)
      assert conn.telegram_id == "12345"
      assert conn.user_id == scope.user.id
    end

    test "updates existing connection on re-connect", %{scope: scope} do
      attrs = %{
        "telegram_id" => "12345",
        "first_name" => "Alice",
        "connected_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, _} = TelegramConnections.upsert_connection(scope, attrs)

      {:ok, updated} =
        TelegramConnections.upsert_connection(scope, Map.put(attrs, "first_name", "Alicia"))

      assert updated.first_name == "Alicia"
      assert Repo.aggregate(TelegramConnection, :count) == 1
    end
  end

  describe "delete_connection/1" do
    test "deletes existing connection", %{scope: scope} do
      {:ok, _} =
        TelegramConnections.upsert_connection(scope, %{
          "telegram_id" => "999",
          "first_name" => "Bob",
          "connected_at" => DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:ok, _} = TelegramConnections.delete_connection(scope)
      assert TelegramConnections.get_connection(scope) == nil
    end

    test "returns ok when no connection exists", %{scope: scope} do
      assert {:ok, nil} = TelegramConnections.delete_connection(scope)
    end
  end
end
