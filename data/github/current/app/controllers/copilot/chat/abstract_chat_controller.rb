# typed: true
# frozen_string_literal: true

class Copilot::Chat::AbstractChatController < ApplicationController
  abstract!

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ApplicationHelper
  include CopilotAuthHelper
  include CurrentRepositoryInteractionsHelper
  include ReactHelper

  before_action :require_logged_in_user
  before_action :require_feature_enabled
  before_action :require_user_can_read_repo

  private

  # NOTE: we have a `login_required` method available to all controllers
  # that redirects to /login if the user is not logged in but
  # we want to render a 404 to avoid leaking any info about the feature
  def require_logged_in_user
    render_404 unless logged_in?
  end

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    helpers.copilot_chat_enabled_for_current_user?
  end

  memoize def require_user_can_read_repo
    return unless current_repository
    render_404 unless current_user_can_read_repo?
  end

  def report_error(e)
    Failbot.report(e)
    GitHub.dogstats.increment("copilot.chat.error", tags: [
      "error:#{e.class.name}",
      "action:#{action_name}",
    ])
  end

  sig { returns Copilot::User::CopilotApi }
  def current_user_copilot_api
    token = GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])
    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
      token: token,
    )
  end
end
