# typed: true
# frozen_string_literal: true

# TODO remove as part of https://github.com/github/pull-requests/issues/15546

class Settings::DiffLineSpacingController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :require_xhr
  before_action :validate_params
  allow_verified_fetch only: [:update]

  def update
    return head :not_found unless logged_in?

    value = params[:diff_line_spacing]
    current_user.settings.set!(:diff_line_spacing, value)

    GitHub.dogstats.increment("diff_line_spacing_preference.update", tags: ["value:#{value}"])

    head :ok
  end

  private

  def validate_params
    head :not_found unless params[:diff_line_spacing].present?
    head :not_found unless [Commit::DiffLineSpacing::RELAXED, Commit::DiffLineSpacing::COMPACT].include?(params[:diff_line_spacing])
  end
end
