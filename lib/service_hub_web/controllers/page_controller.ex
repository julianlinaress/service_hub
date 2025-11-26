defmodule ServiceHubWeb.PageController do
  use ServiceHubWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
