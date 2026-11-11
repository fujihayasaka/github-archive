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
  include GitHub::ResilienceMixin

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
    # If the user can't read the repository, treat it as if no repository
    # context was provided (set to nil) rather than rendering a 404.
    # This prevents private repository existence enumeration via the
    # Referer header: an inaccessible repo and a non-existent repo both
    # result in a 200 response with no repository context.
    @all_memoized[:current_repository] = nil unless current_user_can_read_repo?
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
    {
      **immersive_chat_payload_lite,
      **immersive_chat_deferred_payload,
    }
  end

  # Fields that do NOT require the Copilot user cache.
  # Used by the embedded immersive panel for fast initial page load.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def immersive_chat_payload_lite
    user = T.must(current_user)
    {
      searchWorkerFilePath: find_file_worker_path,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: with_database_error_fallback(fallback: false) { user.settings.get(:copilot_editor_upsell_banner_dismissed) },
      showCopilotSpacesMcpBanner: with_database_error_fallback(fallback: false) { !user.dismissed_notice?(:copilot_spaces_install_mcp_banner) },
      previewUrl: Viewscreen.host_url,
      helpUrl: GitHub.help_url,
      **helpers.copilot_chat_payload_lite(false, saml_authorized_organizations(cap_filter, user), request),
      spark: {
        icebreakers: helpers.get_spark_icebreakers_json,
      },
      copilotSpacesConfig: {
        maxDescriptionLength: CopilotSpace::MAX_DESCRIPTION_LENGTH,
        maxGeneralInstructionsLength: CopilotSpace::MAX_GENERAL_INSTRUCTIONS_LENGTH,
        maxContentSize: CopilotSpace.max_content_size(current_user),
        maxResourceCount: CopilotSpace::MAX_RESOURCE_COUNT,
        userHasOrgs: with_database_error_fallback(fallback: false) { user.organizations.exists? },
      },
      showCopilotCodingAgentPremiumRequestsBanner: with_database_error_fallback(fallback: false) { CopilotSessions::Public.show_copilot_coding_agent_premium_requests_banner(user) },
      currentUser: CopilotSessions::Payloads::PublicUser.new(user).call,
    }
  end

  # Fields that require the Copilot user cache (Copilot::Public::User / Copilot::UserCache).
  # Fetched asynchronously by the embedded immersive panel after it opens.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def immersive_chat_deferred_payload
    user = T.must(current_user)
    {
      copilotChatSettingEnabled: helpers.copilot_chat_enabled_for_current_user?,
      agentsEnabled: with_database_error_fallback(fallback: false) { Copilot::Public::User.for(user).swe_agent_enabled? },
      sparkEnabled: with_database_error_fallback(fallback: false) { user.spark_enabled? },
      memberRequestEntities: with_database_error_fallback(fallback: {}) { helpers.get_member_requests_payload(user) },
      **helpers.copilot_chat_deferred_payload,
    }
  end
end
