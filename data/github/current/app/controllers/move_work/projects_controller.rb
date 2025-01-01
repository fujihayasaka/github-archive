# typed: true
# frozen_string_literal: true

class MoveWork::ProjectsController < MoveWork::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests

  def index
    render Sculk::MoveWork::ProjectsComponent.new(
      actor: current_context,
      total_resources: params[:total_resources],
      loaded_resources:  params[:loaded_resources]&.to_i || 0,
    ), layout: false
  end
end
