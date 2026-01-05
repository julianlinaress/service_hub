defmodule ServiceHubWeb.AuthTypeLiveTest do
  use ServiceHubWeb.ConnCase

  import Phoenix.LiveViewTest
  import ServiceHub.ProvidersFixtures

  @create_attrs %{key: "github_pat"}
  @update_attrs %{key: "github_oauth"}

  setup :register_and_log_in_user

  defp create_auth_type(%{scope: scope}) do
    auth_type = auth_type_fixture(scope)

    %{auth_type: auth_type}
  end

  describe "Index" do
    setup [:create_auth_type]

    test "lists all auth_types", %{conn: conn, auth_type: auth_type} do
      {:ok, _index_live, html} = live(conn, ~p"/config/auth-types")

      assert html =~ "Listing Auth types"
      assert html =~ auth_type.name
    end

    test "saves new auth_type", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/config/auth-types")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Auth type")
               |> render_click()
               |> follow_redirect(conn, ~p"/config/auth-types/new")

      assert render(form_live) =~ "New Auth type"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#auth_type-form", auth_type: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/config/auth-types")

      html = render(index_live)
      assert html =~ "Auth type created successfully"
      assert html =~ "GitHub personal access token"
    end

    test "updates auth_type in listing", %{conn: conn, auth_type: auth_type} do
      {:ok, index_live, _html} = live(conn, ~p"/config/auth-types")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#auth_types-#{auth_type.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/config/auth-types/#{auth_type}/edit")

      assert render(form_live) =~ "Edit Auth type"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#auth_type-form", auth_type: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/config/auth-types")

      html = render(index_live)
      assert html =~ "Auth type updated successfully"
      assert html =~ "GitHub OAuth (3-legged)"
    end

    test "deletes auth_type in listing", %{conn: conn, auth_type: auth_type} do
      {:ok, index_live, _html} = live(conn, ~p"/config/auth-types")

      assert index_live |> element("#auth_types-#{auth_type.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#auth_types-#{auth_type.id}")
    end
  end

  describe "Show" do
    setup [:create_auth_type]

    test "displays auth_type", %{conn: conn, auth_type: auth_type} do
      {:ok, _show_live, html} = live(conn, ~p"/config/auth-types/#{auth_type}")

      assert html =~ "Auth type"
      assert html =~ auth_type.name
    end

    test "updates auth_type and returns to show", %{conn: conn, auth_type: auth_type} do
      {:ok, show_live, _html} = live(conn, ~p"/config/auth-types/#{auth_type}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit auth_type")
               |> render_click()
               |> follow_redirect(conn, ~p"/config/auth-types/#{auth_type}/edit?return_to=show")

      assert render(form_live) =~ "Edit Auth type"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#auth_type-form", auth_type: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/config/auth-types/#{auth_type}")

      html = render(show_live)
      assert html =~ "Auth type updated successfully"
      assert html =~ "GitHub OAuth (3-legged)"
    end
  end
end
