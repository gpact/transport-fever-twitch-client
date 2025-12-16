defimpl String.Chars, for: ExIRC.SenderInfo do
  def to_string(%ExIRC.SenderInfo{nick: nick, user: user, host: host}) do
    nick = to_bin(nick)
    user = to_bin(user)
    host = to_bin(host)

    cond do
      nick == "" and user == "" and host == "" ->
        "*"

      user == "" and host == "" ->
        nick

      nick == "" ->
        "#{user}@#{host}"

      true ->
        "#{nick}!#{user}@#{host}"
    end
  end

  defp to_bin(value) when is_binary(value), do: value
  defp to_bin(value) when is_list(value), do: List.to_string(value)
  defp to_bin(nil), do: ""
  defp to_bin(_), do: ""
end

