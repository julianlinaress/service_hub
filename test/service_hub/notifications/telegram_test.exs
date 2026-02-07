defmodule ServiceHub.Notifications.TelegramTest do
  use ExUnit.Case, async: true

  alias ServiceHub.Notifications.Telegram

  describe "extract_destinations_from_updates/1" do
    test "extracts and deduplicates destinations" do
      updates = [
        %{"message" => %{"chat" => %{"id" => -100, "title" => "Ops", "type" => "group"}}},
        %{"message" => %{"chat" => %{"id" => -100, "title" => "Ops", "type" => "group"}}},
        %{
          "channel_post" => %{
            "chat" => %{"id" => -200, "username" => "deployments", "type" => "channel"}
          }
        }
      ]

      destinations = Telegram.extract_destinations_from_updates(updates)

      assert length(destinations) == 2
      assert Enum.any?(destinations, &(&1.chat_ref == "-100" and &1.title == "Ops"))
      assert Enum.any?(destinations, &(&1.chat_ref == "@deployments"))
    end
  end
end
