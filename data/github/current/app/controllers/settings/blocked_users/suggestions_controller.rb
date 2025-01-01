# typed: true
# frozen_string_literal: true

class Settings::BlockedUsers::SuggestionsController < ApplicationController
  before_action :login_required
  before_action :ensure_user_abuse_mitigation_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  SUGGESTIONS_LIMIT = 10

  def index
    headers["Cache-Control"] = "no-cache, no-store"

    suggestions = User.search(params[:q], limit: SUGGESTIONS_LIMIT)

    render partial: "settings/blocked_users/suggestions/index", formats: :html, locals: {
      suggestions: suggestions,
    }
  end

  private

  def ensure_user_abuse_mitigation_enabled
    render_404 unless GitHub.user_abuse_mitigation_enabled?
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
