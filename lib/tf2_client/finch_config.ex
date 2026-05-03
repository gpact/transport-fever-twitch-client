defmodule TF2Client.FinchConfig do
  @moduledoc false

  def child_spec do
    {Finch, name: TF2Client.Finch, pools: %{default: [conn_opts: [transport_opts: transport_opts()]]}}
  end

  def transport_opts do
    [cacertfile: CAStore.file_path()]
  end
end
