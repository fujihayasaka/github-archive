# typed: true
# frozen_string_literal: true

class Actions::SurveyController < AbstractRepositoryController
  include ActionsControllerMethods
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:open, :dismiss]

  before_action :login_required
  before_action :actions_enabled_for_repo?
  before_action :should_show_selected_workflow_run?

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found if GitHub.enterprise?

    Actions::Survey::dismiss_survey(current_user)

    head :ok
  end

  def open # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found if GitHub.enterprise?

    Actions::Survey::opened_survey(current_user)

    head :ok
  end
end
