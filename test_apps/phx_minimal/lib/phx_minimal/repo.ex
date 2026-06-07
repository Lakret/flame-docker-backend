defmodule PhxMinimal.Repo do
  use Ecto.Repo,
    otp_app: :phx_minimal,
    adapter: Ecto.Adapters.SQLite3
end
