# typed: strict
# frozen_string_literal: true

class MoveWork::RepositoriesController < MoveWork::BaseController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:index]


  sig { void }
  def index
    render Sculk::MoveWork::RepositoriesComponent.new(
      actor: current_context,
      total_resources: params[:total_resources],
      loaded_resources:  params[:loaded_resources]&.to_i || 0,
      selected_resource_name: params[:repository],
    ), layout: false
  end
end
