defmodule ServiceHubWeb.PageController do
  use ServiceHubWeb, :controller

  def home(conn, _params) do
    # Redirect authenticated users to dashboard
    if conn.assigns[:current_scope] do
      redirect(conn, to: "/dashboard")
    else
      render(conn, :home)
    end
  end
end
