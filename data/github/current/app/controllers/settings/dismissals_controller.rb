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
  def create
    notice_name = params[:notice]

    if AUTHENTICATION_CUSTOM_DISMISSAL_NOTICES.include?(notice_name)
      # Dismiss on the authentication KV store with a 90-day expiry
      current_user.dismiss_notice(notice_name, expires: SNOOZE_INTERVAL_90D.from_now, kv_store: GitHub::Authentication::KV.store)
    else
      group = params[:group].present? ? params[:group].to_sym : nil
      InProductTargeting::NudgeMemory.new(current_user).save_a_copy_of_dismissal_analytics_to_dotcom(id: notice_name, group: group) if params[:nudge].present? && params[:nudge] == "true"

      if GlobalNotices.domain.snooze(user: current_user, name: notice_name.to_sym).is_a?(GH::Result::Error)
        # This might happen if the provided name isn't a global notice name. In that case we just snooze that name.
        current_user.dismiss_notice(notice_name)
      else
        # We successfully snoozed the global notice, celebrate this with datadog.
        GitHub.dogstats.increment("global_notice.snooze", tags: ["notice:#{notice_name}"])
      end
    end

    if request.xhr? || request.format.present? && request.format.json?
      head :ok
    else
      redirect_to :back
    end
  end

  SNOOZE_INTERVAL_90D = T.let(90.days, ActiveSupport::Duration)

  # Authentication notices that are dismissed on the Authentication KV store with a 90-day expiry.
  AUTHENTICATION_CUSTOM_DISMISSAL_NOTICES = T.let([
    UserNotice::STATELESS_S2S_TOKEN_FORMAT_CHANGE_NOTICE,
  ].freeze, T::Array[String])
end
