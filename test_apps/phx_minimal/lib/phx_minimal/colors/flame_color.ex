defmodule PhxMinimal.Colors.FlameColor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flame_colors" do
    field :color, :string
    field :runner_node, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flame_color, attrs) do
    flame_color
    |> cast(attrs, [:color, :runner_node])
    |> validate_required([:color, :runner_node])
  end
end
