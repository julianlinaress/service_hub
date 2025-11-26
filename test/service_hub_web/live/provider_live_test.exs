defmodule ServiceHubWeb.ProviderLiveTest do
  use ServiceHubWeb.ConnCase

  import Phoenix.LiveViewTest
  import ServiceHub.ProvidersFixtures

  defp create_attrs(provider_type, auth_type) do
    %{
      name: "some name",
      base_url: "https://example.com",
      provider_type_id: provider_type.id,
      auth_type_id: auth_type.id,
      auth_data: %{"token" => "abc"}
    }
  end

  defp update_attrs(provider_type, auth_type) do
    %{
      name: "some updated name",
      base_url: "https://other.example.com",
      provider_type_id: provider_type.id,
      auth_type_id: auth_type.id,
      auth_data: %{"token" => "updated"}
    }
  end

  @invalid_attrs %{
    name: nil,
    base_url: nil,
    auth_type_id: nil,
    provider_type_id: nil,
    auth_data: nil
  }

  setup :register_and_log_in_user

  defp create_provider(%{scope: scope} = context) do
    provider_type = provider_type_fixture(scope)
    auth_type = auth_type_fixture(scope)
    provider = provider_fixture(scope, %{provider_type: provider_type, auth_type: auth_type})

    Map.merge(context, %{provider: provider, provider_type: provider_type, auth_type: auth_type})
  end

  describe "Index" do
    setup [:create_provider]

    test "lists all providers", %{conn: conn, provider: provider} do
      {:ok, _index_live, html} = live(conn, ~p"/providers")

      assert html =~ "Listing Providers"
      assert html =~ provider.name
    end

    test "saves new provider", %{conn: conn, provider_type: provider_type, auth_type: auth_type} do
      {:ok, index_live, _html} = live(conn, ~p"/providers")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Provider")
               |> render_click()
               |> follow_redirect(conn, ~p"/providers/new")

      assert render(form_live) =~ "New Provider"

      assert form_live
             |> form("#provider-form", provider: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#provider-form", provider: create_attrs(provider_type, auth_type))
               |> render_submit()
               |> follow_redirect(conn, ~p"/providers")

      html = render(index_live)
      assert html =~ "Provider created successfully"
      assert html =~ "some name"
    end

    test "updates provider in listing", %{
      conn: conn,
      provider: provider,
      provider_type: provider_type,
      auth_type: auth_type
    } do
      {:ok, index_live, _html} = live(conn, ~p"/providers")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#providers-#{provider.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/providers/#{provider}/edit")

      assert render(form_live) =~ "Edit Provider"

      assert form_live
             |> form("#provider-form", provider: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#provider-form", provider: update_attrs(provider_type, auth_type))
               |> render_submit()
               |> follow_redirect(conn, ~p"/providers")

      html = render(index_live)
      assert html =~ "Provider updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes provider in listing", %{conn: conn, provider: provider} do
      {:ok, index_live, _html} = live(conn, ~p"/providers")

      assert index_live |> element("#providers-#{provider.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#providers-#{provider.id}")
    end
  end

  describe "Show" do
    setup [:create_provider]

    test "displays provider", %{conn: conn, provider: provider} do
      {:ok, _show_live, html} = live(conn, ~p"/providers/#{provider}")

      assert html =~ "Show Provider"
      assert html =~ provider.name
    end

    test "updates provider and returns to show", %{
      conn: conn,
      provider: provider,
      provider_type: provider_type,
      auth_type: auth_type
    } do
      {:ok, show_live, _html} = live(conn, ~p"/providers/#{provider}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/providers/#{provider}/edit?return_to=show")

      assert render(form_live) =~ "Edit Provider"

      assert form_live
             |> form("#provider-form", provider: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#provider-form", provider: update_attrs(provider_type, auth_type))
               |> render_submit()
               |> follow_redirect(conn, ~p"/providers/#{provider}")

      html = render(show_live)
      assert html =~ "Provider updated successfully"
      assert html =~ "some updated name"
    end
  end
end
