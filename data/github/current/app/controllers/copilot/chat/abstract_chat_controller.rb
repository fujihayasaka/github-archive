# typed: true
# frozen_string_literal: true

class Copilot::Chat::AbstractChatController < ApplicationController
  abstract!

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ApplicationHelper
  include CopilotAuthHelper
  include CurrentRepositoryInteractionsHelper
  include Copilot::Chat::ReferenceBuildersDependency
  include CopilotSpaces::FeaturePreviewRedirect

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
    Copilot::User.copilot_api(
      user: T.must(current_user),
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
      token: token,
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def immersive_chat_payload
    user = T.must(current_user)
    {
      copilotChatSettingEnabled: helpers.copilot_chat_enabled_for_current_user?,
      searchWorkerFilePath: find_file_worker_path,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: user.settings.get(:copilot_editor_upsell_banner_dismissed),
      icebreakers: helpers.get_icebreakers_json,
      graphqlApiUrl: "/copilot/loops/loops_execution",
      loopsClientUrl: "/copilot/loops/client",
      loopsExecutionUrl: GitHub.copilot_loops_execution_url,
      previewUrl: Viewscreen.host_url,
      helpUrl: GitHub.help_url,
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, user), request),
      spark: {
        icebreakers: helpers.get_spark_icebreakers_json,
      },
      copilotSpacesConfig: {
        maxDescriptionLength: CopilotSpace::MAX_DESCRIPTION_LENGTH,
        maxGeneralInstructionsLength: CopilotSpace::MAX_GENERAL_INSTRUCTIONS_LENGTH,
        maxContentSize: CopilotSpace.max_content_size(current_user),
        maxResourceCount: CopilotSpace::MAX_RESOURCE_COUNT,
        userHasOrgs: user.organizations.exists?,
      },
      agentsEnabled: Copilot::Public::User.new(user).swe_agent_enabled?,
      showCopilotCodingAgentPremiumRequestsBanner: CopilotSessions::Public.show_copilot_coding_agent_premium_requests_banner(user),
      sparkEnabled: current_user.spark_enabled?,
      loopsEnabled: current_user.loops_enabled?,
      memberRequestEntities: helpers.get_member_requests_payload(user),
    }
  end
end
