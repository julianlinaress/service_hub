defmodule ServiceHubWeb.ProviderTypeLiveTest do
  use ServiceHubWeb.ConnCase

  import Phoenix.LiveViewTest
  import ServiceHub.ProvidersFixtures

  @create_attrs %{
    name: "some name",
    key: "some key",
    required_fields: ~s({"field":{"label":"Field","type":"text"}})
  }
  @update_attrs %{
    name: "some updated name",
    key: "some updated key",
    required_fields: ~s({"updated":{"label":"Updated","type":"password"}})
  }
  @invalid_attrs %{name: nil, key: nil, required_fields: nil}

  setup :register_and_log_in_user

  defp create_provider_type(%{scope: scope}) do
    provider_type = provider_type_fixture(scope)

    %{provider_type: provider_type}
  end

  describe "Index" do
    setup [:create_provider_type]

    test "lists all provider_types", %{conn: conn, provider_type: provider_type} do
      {:ok, _index_live, html} = live(conn, ~p"/provider_types")

      assert html =~ "Listing Provider types"
      assert html =~ provider_type.name
    end

    test "saves new provider_type", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/provider_types")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Provider type")
               |> render_click()
               |> follow_redirect(conn, ~p"/provider_types/new")

      assert render(form_live) =~ "New Provider type"

      assert form_live
             |> form("#provider_type-form", provider_type: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#provider_type-form", provider_type: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/provider_types")

      html = render(index_live)
      assert html =~ "Provider type created successfully"
      assert html =~ "some name"
    end

    test "updates provider_type in listing", %{conn: conn, provider_type: provider_type} do
      {:ok, index_live, _html} = live(conn, ~p"/provider_types")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#provider_types-#{provider_type.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/provider_types/#{provider_type}/edit")

      assert render(form_live) =~ "Edit Provider type"

      assert form_live
             |> form("#provider_type-form", provider_type: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#provider_type-form", provider_type: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/provider_types")

      html = render(index_live)
      assert html =~ "Provider type updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes provider_type in listing", %{conn: conn, provider_type: provider_type} do
      {:ok, index_live, _html} = live(conn, ~p"/provider_types")

      assert index_live
             |> element("#provider_types-#{provider_type.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#provider_types-#{provider_type.id}")
    end
  end

  describe "Show" do
    setup [:create_provider_type]

    test "displays provider_type", %{conn: conn, provider_type: provider_type} do
      {:ok, _show_live, html} = live(conn, ~p"/provider_types/#{provider_type}")

      assert html =~ "Show Provider type"
      assert html =~ provider_type.name
    end

    test "updates provider_type and returns to show", %{conn: conn, provider_type: provider_type} do
      {:ok, show_live, _html} = live(conn, ~p"/provider_types/#{provider_type}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/provider_types/#{provider_type}/edit?return_to=show")

      assert render(form_live) =~ "Edit Provider type"

      assert form_live
             |> form("#provider_type-form", provider_type: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#provider_type-form", provider_type: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/provider_types/#{provider_type}")

      html = render(show_live)
      assert html =~ "Provider type updated successfully"
      assert html =~ "some updated name"
    end
  end
end
