# typed: true
# frozen_string_literal: true

class Copilot::CodeReviewRepositorySettingsController < AbstractRepositoryController
  include ApplicationController::CopilotDependency

  before_action :login_required

  sig { void }
  def create
    return false unless current_repository
    settings = PullRequests::Copilot::CodeReviewRepositorySettings.find_or_create_by(
      repository: current_repository,
    )

    settings.repo_custom_instructions_enabled = params[:value] == "1"

    settings.save!
    head :ok
  end
end
