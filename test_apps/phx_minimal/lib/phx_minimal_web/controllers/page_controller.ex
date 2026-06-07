defmodule PhxMinimalWeb.PageController do
  use PhxMinimalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
