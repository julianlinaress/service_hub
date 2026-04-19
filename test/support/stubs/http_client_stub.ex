defmodule ServiceHub.HTTPClientStub do
  @moduledoc """
  Test stub for HTTP clients (Req). Tests seed responses via the process dictionary:

      Process.put(:http_responses, %{"https://example.com" => {:ok, %{status: 200, body: "ok"}}})

  The stub matches request URLs by checking if the configured URL contains any key from the
  `:http_responses` map. The first match wins. If no key matches, returns a network error.

  Tests can also inspect the last URL called via `:http_last_url` in the process dictionary.
  """

  def request(opts) do
    url = Keyword.get(opts, :url, "")
    Process.put(:http_last_url, url)

    responses = Process.get(:http_responses, %{})

    result =
      Enum.find_value(responses, fn {pattern, response} ->
        if String.contains?(url, pattern), do: response
      end)

    result || {:error, :econnrefused}
  end
end
