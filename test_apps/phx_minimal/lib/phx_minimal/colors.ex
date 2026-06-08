defmodule PhxMinimal.Colors do
  @moduledoc false
  import Ecto.Query
  alias PhxMinimal.Colors.FlameColor
  alias PhxMinimal.Repo

  @spec list_flame_colors() :: [FlameColor.t()]
  def list_flame_colors() do
    FlameColor
    |> order_by([c], desc: c.inserted_at)
    |> limit(50)
    |> Repo.all()
  end

  @spec create_flame_color!(map()) :: FlameColor.t()
  def create_flame_color!(attrs) do
    %FlameColor{}
    |> FlameColor.changeset(attrs)
    |> Repo.insert!()
  end
end
