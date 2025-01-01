# typed: true
# frozen_string_literal: true

class Codespaces::SurveyController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:open, :dismiss]

  before_action :login_required

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.codespaces_enabled?

    Codespaces::Survey::dismiss_survey(current_user)

    head :ok
  end

  def open # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.codespaces_enabled?

    Codespaces::Survey::opened_survey(current_user)

    head :ok
  end

  private

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
