# typed: true
# frozen_string_literal: true

class Settings::UserSessionsController < ApplicationController
  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  before_action :sudo_filter, only: %w( revoke )

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def revoke # rubocop:todo GitHub/UseRestfulActions
    session = current_user.sessions.find(params[:id])
    return render_404 unless session

    session.revoke(:user_remote_revoke)

    GitHub.dogstats.increment("user_session", tags: ["action:destroy", "xhr:#{request.xhr?}"])

    if request.xhr?
      head :ok
    else
      flash[:session_revoked] = true
      redirect_to settings_sessions_path
    end
  end

  # Renders a UserSession, web sign in, or two factor partial sign in events
  # depending on what is requested and what is available. In all cases, render
  # using the familiar sessions UI.
  def show
    session_or_auth_record = if params[:authentication_record_id]
      correct_password_event = current_user.authentication_records.find(params[:authentication_record_id])
      two_factor_sign_in = if correct_password_event&.two_factor_partial_sign_in?
        current_user.authentication_records
          .same_session_as(correct_password_event)
          .subsequent_to(correct_password_event)
          .web_sign_ins.first
      end
      two_factor_sign_in&.user_session || two_factor_sign_in || correct_password_event
    else
      current_user.sessions.user_facing.find_by_id(params[:id]) ||
        # If the session has been deleted, fallback to the web sign in event
        current_user.authentication_records.web_sign_ins.find_by_user_session_id(params[:id])
    end

    unless session_or_auth_record
      flash[:session_not_found] = true
      return redirect_to settings_sessions_path
    end
    render "settings/user/sessions/show", locals: { session_or_auth_record: session_or_auth_record }
  end
end
