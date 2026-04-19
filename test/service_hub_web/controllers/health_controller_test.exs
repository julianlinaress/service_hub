defmodule ServiceHubWeb.HealthControllerTest do
  use ServiceHubWeb.ConnCase, async: true

  test "GET /healthz returns 200 ok", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert response(conn, 200) == "ok"
  end
end
