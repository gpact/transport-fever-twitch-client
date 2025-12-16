defmodule TF2Client.Lua do
  @moduledoc false

  def encode(term), do: encode(term, 0)

  defp encode(nil, _indent), do: "nil"
  defp encode(true, _indent), do: "true"
  defp encode(false, _indent), do: "false"
  defp encode(number, _indent) when is_integer(number) or is_float(number), do: to_string(number)

  defp encode(binary, _indent) when is_binary(binary) do
    "\"" <> escape_string(binary) <> "\""
  end

  defp encode(list, indent) when is_list(list) do
    inner =
      list
      |> Enum.map(&encode(&1, indent + 1))
      |> Enum.join(", ")

    "{ " <> inner <> " }"
  end

  defp encode(map, indent) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {k, v} -> {key_to_string(k), v} end)
      |> Enum.sort_by(fn {k, _} -> k end)

    indent_str = String.duplicate("\t", indent)
    inner_indent_str = String.duplicate("\t", indent + 1)

    inner =
      pairs
      |> Enum.map(fn {k, v} ->
        "#{inner_indent_str}#{encode_key(k)} = #{encode(v, indent + 1)},\n"
      end)
      |> Enum.join()

    "{\n" <> inner <> indent_str <> "}"
  end

  defp encode_key(key) when is_binary(key) do
    if Regex.match?(~r/^[_A-Za-z][_0-9A-Za-z]*$/, key) do
      key
    else
      "[\"" <> escape_string(key) <> "\"]"
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: to_string(key)

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
