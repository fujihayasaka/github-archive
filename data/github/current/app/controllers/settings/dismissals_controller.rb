# typed: true
# frozen_string_literal: true

class Settings::DismissalsController < ApplicationController

  # The following actions do not require conditional access checks:
  # - show: doesn't access any protected organizations so
  # it doesn't require external session verification.
  # - create: doesn't access any protected organizations so
  # it doesn't require external session verification.
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: [:show, :create]

  before_action :login_required

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:show]

  # Check if the named notice has been dismissed by the current user.
  def show
    if request.xhr?
      render json: { dismissed: current_user.dismissed_notice?(params[:notice]) }
    else
      redirect_to :back
    end
  end

  # The browser performs a set to keyvalues when a POST request to /dismiss-notice/:notice
  #
  # Returns nothing.
  def create
    notice_name = params[:notice]

    global_notice = GlobalNoticeNext.new(viewer: current_user)
    if notice_name&.to_sym == global_notice.current_notice_name && global_notice.current_notice.can_snooze?
      GitHub.dogstats.increment("global_notice.snooze", tags: ["notice:#{params[:notice]}"])
      global_notice.current_notice.snooze
    else
      current_user.dismiss_notice(notice_name)
    end

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
