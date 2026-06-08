defmodule PhxMinimal.Repo.Migrations.CreateFlameColors do
  use Ecto.Migration

  def change do
    create table(:flame_colors) do
      add :color, :string
      add :runner_node, :string

      timestamps(type: :utc_datetime)
    end
  end
end
