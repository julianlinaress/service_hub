defmodule ServiceHub.Notifications.Helpers do
  @moduledoc false

  def normalize_id(value) when is_integer(value), do: value

  def normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  def normalize_id(_), do: nil

  def get_value(map, key) when is_map(map) do
    atom_key = to_existing_atom(key)

    case {Map.get(map, key), atom_key} do
      {nil, nil} -> nil
      {nil, atom} -> Map.get(map, atom)
      {value, _} -> value
    end
  end

  def get_value(_, _), do: nil

  def put_value(map, key, value) when is_map(map) do
    has_atom_keys = Enum.any?(Map.keys(map), &is_atom/1)
    has_string_keys = Enum.any?(Map.keys(map), &is_binary/1)

    if Map.has_key?(map, key) do
      Map.put(map, key, value)
    else
      case to_existing_atom(key) do
        nil ->
          Map.put(map, key, value)

        atom_key ->
          if Map.has_key?(map, atom_key) or (has_atom_keys and not has_string_keys) do
            Map.put(map, atom_key, value)
          else
            Map.put(map, key, value)
          end
      end
    end
  end

  def to_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  def to_existing_atom(_), do: nil

  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(value), do: not is_nil(value)
end
