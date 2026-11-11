# typed: true
# frozen_string_literal: true

begin
  require "rbnacl"
rescue LoadError => e
  raise LoadError, "Missing required dependency rbnacl needed by CopilotChatHelper. Original error: #{e.message}"
end

module CopilotChatHelper
  extend T::Helpers
  include GitHub::Memoizer
  include AvatarHelper
  include FeatureFlagHelper
  include GitHub::ResilienceMixin

  FEATURE_FLAG_TO_PROMPTS = {
    copilot_showcase_icebreakers_include_whats_new: "whats-new-in-copilot",
    copilot_showcase_icebreakers_include_make_pong: "make-pong",
  }

  MEMBER_REQUESTS_ORGS_LIMIT = 10

  # Minimum TTL for Copilot token. The frontend treats tokens within this window as already expired.
  # Keep in sync with COPILOT_CHAT_TOKEN_TTL_PADDING.
  COPILOT_CHAT_TOKEN_TTL_PADDING = 5.minutes

  # How long after a license is granted we consider the copilot-limiter cache to still be warming up.
  # Used to surface the "license provisioning" quota banner on the frontend.
  LICENSE_PROVISIONING_WINDOW = 10.minutes

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
  def current_copilot_user_v2; end

  class CopilotChatAuthError < StandardError; end

  # All users with a license have access by default, except CB/CE which have a setting that must be enabled
  # in order for them to be able to use Copilot Chat on GitHub.
  sig { returns(T::Boolean) }
  memoize def copilot_chat_enabled_for_current_user?
    GitHub.dogstats.increment("copilot_chat_helper.copilot_chat_enabled_for_current_user")
    GitHub.tracer.in_span("copilot_chat_helper.copilot_chat_enabled_for_current_user") do |_span|
      # if we don't have copilot, we can't have chat
      T.cast(GitHub.copilot_enabled?, T::Boolean) &&
      # the circuit breaker - if this is disabled, that means we turned it off and no one gets dotcom chat
      copilot_flag_enabled? &&
      # check the user settings
      dotcom_chat_enabled_for_current_user?
    end
  end

  sig { returns(T::Boolean) }
  memoize def current_user_has_copilot_license?
    copilot_user = current_copilot_user_v2
    return false unless copilot_user
    T.must(copilot_user).has_copilot_access?
  end

  sig { params(repo: T.nilable(Repository), ref_name: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def repo_props(repo:, ref_name: nil)
    return if repo.blank?

    ref_name ||= repo.default_branch
    ref = repo.refs.find(ref_name)

    current_oid = if ref
      ref.target_oid
    elsif GitRPC::Util.valid_full_oid?(ref_name)
      ref_name
    end

    custom_instructions = T.cast([], T::Array[Copilot::CustomInstructions::CustomInstructionJson])

    if repo_custom_instructions_enabled?
      repo_ci_json = if feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_additional_custom_instructions)
        Copilot::CustomInstructions.additional_repository_instructions(repo, current_oid)
      else
        Copilot::CustomInstructions.for_repository(repo, current_oid)
      end

      if repo_ci_json
        custom_instructions.append(repo_ci_json)
      end
    end

    if repo.owner.is_a?(Organization)
      org = T.cast(repo.owner, Organization)

      if org.member?(current_user) && current_user&.feature_preview_enabled?(:copilot_chat_custom_instructions)
        org_ci = Copilot::CustomInstructions.for_organization(org)

        custom_instructions.append(org_ci.as_json) if org_ci && org_ci.prompt.present?
      end
    end

    {
      id: repo.id,
      name: repo.name,
      ownerLogin: repo.owner_display_login,
      ownerType: repo.owning_organization_id.present? ? "Organization" : "User",
      readmePath: repo.preferred_readme&.path,
      description: repo.description,
      commitOID: current_oid.to_s,
      ref: ref&.qualified_name || "refs/heads/#{repo.default_branch}",
      refInfo: {
        name: ref&.name || repo.default_branch,
        type: ref&.tag? ? "tag" : "branch",
      },
      visibility: repo.visibility,
      languages: repo.top_languages_summarized.map { |name, percent| { name: name, percent: percent } },
      customInstructions: custom_instructions,
      defaultBranch: repo.default_branch,
      ownerAvatarUrl: T.must(repo.owner).primary_avatar_url,
    }
  end

  sig { returns(T::Boolean) }
  def copilot_flag_enabled?
    # this is a circuit breaker. if it is NOT enabled, we don't try checking stuff
    feature_enabled_globally_or_for_user?(feature_name: :copilot_dotcom_chat)
  end

  sig { returns(T::Boolean) }
  def should_check_licenses?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_conversational_ux_license_check)
  end

  sig { returns(T::Boolean) }
  def dotcom_chat_enabled_for_current_user?
    return true unless should_check_licenses?
    GitHub.dogstats.increment("copilot_chat_helper.dotcom_chat_enabled_for_current_user")
    GitHub.tracer.in_span("copilot_chat_helper.dotcom_chat_enabled_for_current_user") do |_span|
      copilot_user = current_copilot_user_v2
      return false unless copilot_user
      copilot_user.dotcom_chat_enabled?
    end
  end

  sig { returns(T::Boolean) }
  memoize def opted_in_to_user_feedback?
    return false unless current_user

    copilot_user = current_copilot_user_v2
    return false unless copilot_user
    copilot_user.user_feedback_opt_in_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def repo_custom_instructions_enabled?
    copilot_user = current_copilot_user_v2
    return false unless copilot_user
    # the user has free/individual access || the user is opted in to preview features
    copilot_user.has_ci_access? || copilot_user.beta_features_github_chat_enabled?
  end

  # This is a temporary duplicate of packages/copilot_spaces/app/lib/custom_copilots/feature_preview_redirect.rb's
  # copilot_spaces_enabled? method.
  sig { returns(T::Boolean) }
  memoize def copilot_spaces_enabled?
    return false unless current_user
    CopilotSpaces::Enabled.copilot_spaces_enabled_for_user?(T.must(current_user))
  end

  sig { returns(T::Boolean) }
  memoize def custom_copilots_individual_access_enabled?
    return false unless current_user
    Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(T.must(current_user))) == "enabled"
  end

  sig { returns(RbNaCl::SimpleBox) }
  memoize def simple_box
    T.must_because(GitHub.dotcom_capi_simple_box) { "must have an encryption key set" }
  end

  sig { params(user_session: UserSession, entry_point: Symbol).returns(Copilot::EncryptedToken) }
  def copilot_mint_token(user_session, entry_point:)
    user = T.must_because(user_session.user) { "we expect user_session to always have a user" }
    app = T.must_because(copilot_chat_app) { "copilot_chat_app should always be present" }

    new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })

    # NOTE: despite the name `extended_expiry`, we are actually expiring the tokens much sooner than the default.
    #       the flag is used internally to read from the internal app's `oauth_access_expiry` property.
    token, _ = new_access.redeem(extended_expiry: true)

    if entry_point == :copilot_chat_tokens_controller_create
      # Cap the token expiration to the soonest SSO session expiration.
      sso_expiration = copilot_token_expiration_cap(user_session, new_access.expires_at.in_time_zone)
      if sso_expiration
        ActiveRecord::Base.connected_to(role: :writing) do
          OauthAccessTokens.domain.set_expiration(new_access.id, sso_expiration.to_time)
        end
        new_access.expires_at = sso_expiration.to_time # skip reload
      end
    end

    encrypted = simple_box.encrypt(token)

    # The encrypted token gets passed around to the browser and ultimately into an HTTP header in requests to CAPI,
    # so it needs to be URL encoded/decoded.
    encoded = Base64.urlsafe_encode64(encrypted)

    Copilot::EncryptedToken.from(encoded, expiration: new_access.expires_at)
  end

  # Returns the soonest SSO expiration time between 5-30 min if any.
  sig { params(user_session: UserSession, current_expires_at: ActiveSupport::TimeWithZone).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def copilot_token_expiration_cap(user_session, current_expires_at)
    earliest_expires_at = ExternalIdentitySession
      .by_user_session(user_session)
      .where(expires_at: Time.current..current_expires_at)
      .minimum(:expires_at)

    return nil unless earliest_expires_at
    [(earliest_expires_at + COPILOT_CHAT_TOKEN_TTL_PADDING), current_expires_at].min
  end

  sig { returns(T.nilable(Integration)) }
  memoize def copilot_chat_app
    ::Apps::Privileged.integration(:copilot_chat)
  end

  def get_integration_agents(sso_organizations)
    return [] if !current_user
    user = T.must(current_user)
    org_sso_ids = sso_organizations.map { |org| org[:id] }
    orgs = user.organizations.map do |org|
      if org_sso_ids.include?(org[:id].to_s)
        org
      end
    end.compact

    show_unauthorized_agents_enabled = feature_enabled_globally_or_for_user?(feature_name: :copilot_autocomplete_unauthorized_agents)

    org_agents = IntegrationAgent.integrations_installed_for_orgs(orgs)
    authed_agents = IntegrationAgent.integrations_authorized_for_user(user)

    owned_agents = show_unauthorized_agents_enabled ? IntegrationAgent.integrations_owned_by_user(user) : []
    public_agents = show_unauthorized_agents_enabled ? IntegrationAgent.public_integrations : []
    user_installed_agents = IntegrationAgent.integrations_installed_for_target(user)
    (owned_agents + public_agents + authed_agents + user_installed_agents + org_agents).uniq(&:id)
  end

  def copilot_chat_payload(scroll_copilot_to_top = false, authorized_organizations = [], request = nil)
    {
      **copilot_chat_payload_lite(scroll_copilot_to_top, authorized_organizations, request),
      **copilot_chat_deferred_payload,
    }
  end

  # Fields that do NOT require the Copilot user cache.
  # Used by the embedded immersive panel for fast initial load.
  sig { params(scroll_copilot_to_top: T::Boolean, authorized_organizations: T::Array[Organization], request: T.nilable(ActionDispatch::Request)).returns(T::Hash[Symbol, T.untyped]) }
  def copilot_chat_payload_lite(scroll_copilot_to_top = false, authorized_organizations = [], request = nil)
    user = T.must(current_user)
    org_ids = authorized_organizations.map(&:id)

    {
      apiURL: copilot_api_url,
      apiVersion: copilot_api_version,
      currentUserLogin: user.display_login,
      customInstructions: with_database_error_fallback(fallback: nil) { get_default_custom_instructions(org_ids, user) }&.as_json,
      customCopilotsEnabled: copilot_spaces_enabled?,
      customCopilotsIndividualAccessEnabled: custom_copilots_individual_access_enabled?,
      personalInstructions: with_database_error_fallback(fallback: nil) { Copilot::CustomInstructions.where(owner_type: "User", owner_id: user.id).first&.prompt },
      reviewLab: GitHub.review_lab?,
      realIp: Rails.env.development? ? T.must(request).remote_ip : nil,
      scrollToTop: scroll_copilot_to_top,
      icebreakers: get_icebreakers_json,
    }
  end

  # Fields that require the Copilot user cache (Copilot::Public::User / Copilot::UserCache).
  # These are fetched asynchronously by the embedded immersive panel after it opens.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def copilot_chat_deferred_payload
    user = T.must(current_user)
    copilot_user = current_copilot_user_v2
    return {} unless copilot_user

    payload = {
      optedInToPreviewFeatures: copilot_user.beta_features_github_chat_enabled?,
      optedInToUserFeedback: opted_in_to_user_feedback?,
      renderBetaLabel: render_beta_label?,
      hasCEorCBAccess: (copilot_user.has_ce_access? || copilot_user.has_cb_access?),
      licenseType: license_type,
      plan: feature_enabled_globally_or_for_user?(feature_name: :copilot_premium_request_quotas) ? user_plan : nil,
      quotas: user_quotas,
      agentQuotaSnapshot: agent_quota_snapshot_for_user(user),
      canShareThread: CopilotPLG.domain.user_can_share_copilot_thread?(current_user),
      thirdPartyMcpAllowed: copilot_user.mcp_enabled?,
      showDecoupledPRModeBanner: CopilotSessions::Public.show_decoupled_mode_banner(user),
    }

    payload[:licenseProvisioning] = true if license_provisioning?

    if FeatureFlag.vexi.enabled?(:copilot_user_can_upgrade_plan_field, user, default: false)
      payload[:canUpgradePlan] = copilot_user.can_upgrade_plan?
    end

    payload
  end

  # Fetches the current user's quota snapshot from the limiter client.
  sig { params(user: User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def agent_quota_snapshot_for_user(user)
    Copilot::Users::AgentQuotaSnapshot.new.build(user: user)
  end

  memoize def license_type
    copilot_user = current_copilot_user_v2
    return "unlicensed" unless copilot_user

    return "unlicensed" unless copilot_user.has_copilot_access?

    copilot_user.has_limited_access? ? "licensed_limited" : "licensed_full"
  end

  memoize def user_plan
    copilot_user = current_copilot_user_v2
    return nil unless copilot_user
    return nil unless copilot_user.has_copilot_access? || !feature_enabled_globally_or_for_user?(feature_name: :copilot_premium_request_quotas)

    return "edu" if feature_enabled_globally_or_for_user?(feature_name: "copilot_student_dotcom_chat_ui") && copilot_user.has_educational_access?
    return "free" if copilot_user.has_limited_access?
    return "pro" if copilot_user.has_pro_access?
    return "pro_plus" if copilot_user.has_pro_plus_access?
    return "max" if copilot_user.has_max_access?
    return "enterprise" if copilot_user.has_ce_access? # order is important here since enterprise users also have business access
    "business" if copilot_user.has_cb_access?
  end

  memoize def user_quotas
    copilot_user = current_copilot_user_v2
    return nil unless copilot_user

    unless copilot_user.has_limited_access? || feature_enabled_globally_or_for_user?(feature_name: "copilot_premium_request_quotas")
      if current_user&.feature_flag_enabled?(:copilot_limiter_debug_chat_quotas, default: false)
        GitHub.logger.info(
          "Debugging Copilot Chat Quotas ; got nil",
          "gh.user.id" => current_user&.id,
        )
      end
      return nil
    end

    limited_user = Copilot::LimitedUser.for_subscribed_user(T.must(current_user))

    limits = copilot_user.has_limited_access? && !feature_enabled_globally_or_for_user?(feature_name: "copilot_premium_request_quotas") ? Copilot::Quotas.monthly_quotas : {}

    remaining = limited_user ? limited_user.quotas_remaining : {}

    quota_snapshots = copilot_user.quota_snapshots

    if quota_snapshots && quota_snapshots["premium_interactions"] && feature_enabled_globally_or_for_user?(feature_name: "copilot_premium_request_quotas")
      # TODO these need to go past May 8, 2025, just keeping here for compatibility with the old code
      limits["premiumInteractions"] = quota_snapshots["premium_interactions"][:entitlement]
      remaining["premiumInteractions"] = quota_snapshots["premium_interactions"][:remaining]
      # we shall only rely on percentage remaining, since the absolute numbers can be outdated
      remaining["chatPercentage"] = copilot_user.quota_percentage_remaining(feature: "chat")
      remaining["premiumInteractionsPercentage"] = copilot_user.quota_percentage_remaining(feature: "premium_interactions")
    end

    quotas = {
      limits: limits,
      remaining: remaining,
      resetDate: copilot_user.quota_reset_date,
      resetDateUtc: copilot_user.quota_reset_date_utc,
      overagesEnabled: copilot_user.overages_enabled?,
    }

    if copilot_user.use_token_based_billing?
      quotas[:tokenBasedBillingEnabled] = true
      quotas[:chatQuota] = build_quota_limit(quota_snapshots["chat"])
      quotas[:completionsQuota] = build_quota_limit(quota_snapshots["completions"])
      quotas[:premiumInteractionsQuota] = build_quota_limit(quota_snapshots["premium_interactions"])
      quotas[:overageQuota] = build_cfi_overage(copilot_user, quota_snapshots["premium_interactions"])
    end

    if current_user&.feature_flag_enabled?(:copilot_limiter_debug_chat_quotas, default: false)
      GitHub.logger.info(
        "Debugging Copilot Chat Quotas",
        "gh.user.id" => current_user&.id,
        "gh.user.quotas" => quotas,
      )
    end

    quotas
  end

  sig do
    params(snapshot: T.nilable(T::Hash[Symbol, T.untyped]))
      .returns({ percentRemaining: T.nilable(Float), hasQuota: T::Boolean, unlimited: T::Boolean, total: T.nilable(Integer), used: T.nilable(Float) })
  end
  def build_quota_limit(snapshot)
    return { percentRemaining: nil, hasQuota: false, unlimited: false, total: nil, used: nil } unless snapshot

    percent_remaining = (snapshot[:percent_remaining] || 0).to_f
    percent_remaining = [[percent_remaining, 0.0].max, 100.0].min

    {
      percentRemaining: percent_remaining,
      total: snapshot[:entitlement],
      used: snapshot[:entitlement].to_f - snapshot[:remaining].to_f,
      hasQuota: snapshot[:has_quota] || false,
      unlimited: snapshot[:unlimited] || false,
    }
  end
  private :build_quota_limit

  sig do
    params(copilot_user: T.any(Copilot::User, Copilot::Public::User), snapshot: T.nilable(T::Hash[Symbol, T.untyped]))
      .returns({ percentRemaining: T.nilable(Float), permitted: T::Boolean, budget: T.nilable(Float), spend: T.nilable(Float) })
  end
  def build_cfi_overage(copilot_user, snapshot)
    return { percentRemaining: nil, permitted: false, budget: nil, spend: nil } unless snapshot

    permitted = snapshot[:overage_permitted] || false

    default_data = {
      permitted: permitted,
      percentRemaining: 100.0,
      budget: nil,
      spend: nil,
    }

    customer = copilot_user.user_object.customer
    return default_data unless customer

    result = Copilot::QuotaDataHelper.fetch_budget_spend(
      client: Billing::Platform::Api::Client.new,
      customer_id: customer.id.to_s,
    )
    return default_data unless result

    budget_amount = result[:target_amount]
    current_spend = result[:current_spend]
    percent_used = budget_amount > 0 ? ((current_spend / budget_amount.to_f) * 100).clamp(0.0, 100.0) : 0.0

    {
      permitted: permitted,
      percentRemaining: 100.0 - percent_used,
      budget: budget_amount.to_f,
      spend: current_spend,
    }
  end
  private :build_cfi_overage

  memoize def user_trial
    copilot_user = current_copilot_user_v2
    return nil unless copilot_user
    return nil unless feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_include_trial_details)
    return nil unless copilot_user.has_copilot_access?

    result = { eligible: copilot_user.eligible_for_trial? }
    result[:daysLeft] = copilot_user.days_left_on_trial if copilot_user.has_trial_access?
    result
  end

  # Returns true when the user is licensed but copilot-limiter's quota cache
  # may not yet have been populated for them. The frontend uses this to surface
  # a transient "Setting up your Copilot license" banner.
  #
  # We approximate the "limiter still warming" condition using license-grant
  # recency: if the user became licensed within `LICENSE_PROVISIONING_WINDOW`,
  # the limiter cache may not yet be authoritative. After the window passes,
  # the banner stops appearing even if the cache somehow remains cold.
  sig { returns(T::Boolean) }
  memoize def license_provisioning?
    user = current_user
    return false unless user
    return false unless FeatureFlag.vexi.enabled?(:copilot_chat_license_provisioning_banner, user, default: false)

    copilot_user = current_copilot_user_v2
    return false unless copilot_user&.has_copilot_access?

    granted_at = license_granted_at(copilot_user, user)
    return false unless granted_at

    granted_at >= LICENSE_PROVISIONING_WINDOW.ago
  end

  sig { params(copilot_user: T.any(Copilot::User, Copilot::Public::User), user: ::User).returns(T.nilable(Time)) }
  def license_granted_at(copilot_user, user)
    if copilot_user.has_limited_access?
      Copilot::LimitedUser.for_subscribed_user(user)&.subscribed_at
    else
      Copilot::Seat.for_user(user).maximum(:created_at)
    end
  end
  private :license_granted_at

  sig { returns(String) }
  memoize def copilot_api_url
    return Copilot::SKUIsolation.for_user(current_user).api.endpoint unless current_user.present?

    user = T.must(current_user)
    if user.feature_flag_enabled?(:copilot_sku_isolation_use_public_user_perf, default: false)
      sku_isolation = Copilot::SKUIsolation.for_user(user, public_user_enabled: true)
      GitHub.logger.info(
              "Getting SKU Isolation in copilot chat with Public User",
              "gh.user.id" => user.id,
              "gh.copilot.sku_isolation.api_host" => sku_isolation.api.host,
            )
      sku_isolation.api.endpoint
    else
      Copilot::SKUIsolation.for_user(current_user).api.endpoint
    end
  end

  # Show Copilot Chat entrypoints (e.g. chat icon in header) if either of the following are true:
  # - The user is unlicensed and not geo-blocked, and copilot free is enabled
  # - The user is licensed and has access to Copilot Chat
  sig { returns(T::Boolean) }
  memoize def show_copilot_chat_entrypoint?
    return false unless GitHub.copilot_enabled?
    return false if copilot_hidden_by_preference?
    return false if GitHub.multi_tenant_enterprise? && !current_user_has_copilot_license?
    return true if unlicensed_and_unblocked_user?

    copilot_chat_enabled_for_current_user?
  end

  # Show Spark dashboard entrypoints.
  # It's not as nice of an experience, but we skip FF checks on org + enterprise
  # because we can't safely touch the copilot cluster from the global header.
  # This is an edge case only until we've rolled out CB, so we'll live with it.
  sig { returns(T::Boolean) }
  memoize def show_spark_entrypoint?
    return false unless current_user
    return false unless T.must(current_user).spark_enabled?(check_hierarchy: false)

    return false unless GitHub.copilot_enabled?
    return true if unlicensed_and_unblocked_user?

    copilot_chat_enabled_for_current_user?
  end

  sig { returns(T::Boolean) }
  memoize def unlicensed_and_unblocked_user?
    return false unless current_user
    return false if current_user_has_copilot_license?
    copilot_user = Copilot::User.new(T.must(current_user))
    restrictor = Copilot::Authorization::TradeRestrictor.new(copilot_user)

    T.cast(GitHub.context.present?, T::Boolean) && !restrictor.restricted?(GitHub.context, {})
  end

  sig { returns(T::Boolean) }
  memoize def copilot_hidden_by_preference?
    copilot_user = current_copilot_user_v2
    return false unless copilot_user
    !copilot_user.show_copilot_functionality?
  end

  sig { returns(T::Boolean) }
  def render_beta_label?
    return false if current_user&.feature_flag_enabled?(:copilot_chat_dotcom_ga, default: true)
    !current_copilot_user_v2&.has_ce_access?
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def get_icebreakers_json
    showcase_icebreakers_features = FEATURE_FLAG_TO_PROMPTS.keys << :copilot_showcase_icebreakers
    FeatureFlag.vexi.preload(showcase_icebreakers_features, instrumentation_properties: { "code.namespace": "copilot_chat_helper" })

    if FeatureFlag.vexi.enabled?(:copilot_showcase_icebreakers, current_user, default: false)
      file_path = Rails.root.join("config/copilot-icebreakers-showcase.json")
    else
      file_path = Rails.root.join("config/copilot-icebreakers.json")
    end
    data = JSON.parse(File.read(file_path))

    if FeatureFlag.vexi.enabled?(:copilot_showcase_icebreakers, current_user, default: false)
      prompts_to_remove = []
      FEATURE_FLAG_TO_PROMPTS.each do |flag, prompt|
        if !FeatureFlag.vexi.enabled?(flag, current_user, default: false)
          prompts_to_remove << prompt
        end
      end

      if prompts_to_remove.any?
        data.each do |type, prompts|
          data[type] = prompts.reject { |prompt| prompts_to_remove.include?(prompt["id"]) }
        end
      end
    end

    [
      { type: "functional", data: data["functional"] || [] },
      { type: "instructional", data: data["instructional"] || [] },
      { type: "interactional", data: data["interactional"] || [] }
    ]
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def get_spark_icebreakers_json
    file_path = Rails.root.join("config/spark-icebreakers.json")
    data = JSON.parse(File.read(file_path))
    [
      { type: "functional", data: data["functional"] || [] },
      { type: "instructional", data: data["instructional"] || [] },
      { type: "interactional", data: data["interactional"] || [] }
    ]
  end

  sig { returns(T::Array[T.untyped]) }
  def get_nux_icebreakers
    return [] unless current_user&.in_onboarding_period?
    file_path = Rails.root.join("config/copilot-icebreakers-nux.json")
    return [] unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))

    data.fetch("instructional", [])
  end

  sig { params(num_icebreakers: Integer).returns(T::Array[T.untyped]) }
  def get_icebreakers(num_icebreakers)
    icebreakers = get_icebreakers_json
    functional_icebreakers = icebreakers.find { |section| section[:type] == "functional" }&.dig(:data) || []
    instructional_icebreakers = icebreakers.find { |section| section[:type] == "instructional" }&.dig(:data) || []
    functional_icebreakers.concat(instructional_icebreakers).sample(num_icebreakers)
  end

  sig { params(org_ids: T::Array[Integer], user: User).returns(T.nilable(Copilot::CustomInstructions)) }
  def get_default_custom_instructions(org_ids, user)
    return nil unless user.feature_preview_enabled?(:copilot_chat_custom_instructions)

    default_org_id = user.settings.get(:copilot_default_org_custom_instructions)

    custom_instructions = get_custom_instructions(org_ids)

    # if the user did not specify a default org, we return the first available custom instructions
    custom_instructions.find { |ci| ci.owner.id == default_org_id } || custom_instructions.first
  end

  sig { params(org_ids: T::Array[Integer]).returns(T::Array[Copilot::CustomInstructions]) }
  def get_custom_instructions(org_ids)
    user = T.must(current_user)

    custom_instructions = Copilot::CustomInstructions.where(owner_id: org_ids, owner_type: "Organization").includes(:owner)

    custom_instructions.filter do |custom_instructions|
      custom_instructions.prompt.present? && Copilot::Organization.new(custom_instructions.owner).can_use_org_copilot_custom_instructions?
    end
  end

  sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
  def get_member_requests_payload(user)
    payload = {}

    copilot_user = Copilot::Public::User.for(user)
    return payload if copilot_user.swe_agent_enabled? || copilot_user.copilot_businesses.length > 1

    business = copilot_user.copilot_businesses.first

    is_biz_admin, policy_biz_disabled = false, false

    if business
      return payload if business.swe_agent_enabled?
      policy_biz_disabled = business.swe_agent_disabled? || business.swe_agent_unconfigured?
      is_biz_admin = business.business_object.adminable_by?(user)
      payload[:enterprise] = {
        name: business.business_object.display_login,
        isAdmin: is_biz_admin,
        policyDisabled: policy_biz_disabled
      }
    end

    payload[:orgs] = { requestable: [], adminable: [] }

    # user more likely to have less orgs than business
    sorted_orgs = copilot_user.copilot_organizations.sort_by do |org|
      # Sort adminable orgs first (true => 0, false => 1)
      is_org_admin = org.organization_object.adminable_by?(user)
      is_org_admin ? 0 : 1
    end

    sorted_orgs.each do |org|
      break if payload[:orgs][:requestable].count + payload[:orgs][:adminable].count >= MEMBER_REQUESTS_ORGS_LIMIT
      next unless org.copilot_business&.business_object == business&.business_object

      # NOTE: The can request feature method does not take into account when the admin of an org can
      # request on behalf of the org, so we need to check both conditions here
      is_org_admin = org.organization_object.adminable_by?(user)

      can_request_org = MemberFeatureRequest.can_request?(user, org.organization_object, MemberFeatureRequest::Feature::CopilotCodingAgent)
      can_request_biz = business.present? && !is_biz_admin && is_org_admin && policy_biz_disabled # will this run?

      is_adminable = is_org_admin && !policy_biz_disabled
      is_requestable = can_request_org || can_request_biz

      # If the enterprise policy is "no policy", adminable orgs can be shown
      # If the enterprise policy is disabled, only requestable orgs can be shown (and adminable orgs are treated as requestable)
      if is_requestable
        payload[:orgs][:requestable] << member_request_org_object(user, org.organization_object, is_org_admin)
      elsif is_adminable
        payload[:orgs][:adminable] << member_request_org_object(user, org.organization_object, is_org_admin)
      end
    end

    payload
  end

  sig { params(user: User, organization: Organization, is_admin: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def member_request_org_object(user, organization, is_admin)
    billing_entity = is_admin && organization.business ? organization.business : organization

    {
      name: organization.display_login,
      isAdmin: is_admin,
      requestedAccess: MemberFeatureRequest.already_requested?(user, organization, MemberFeatureRequest::Feature::CopilotCodingAgent, billing_entity),
      avatarUrl: organization.primary_avatar_url(20)
    }
  end

  sig { returns(T.nilable(String)) }
  def copilot_api_version
    if current_user&.feature_flag_enabled?(:copilot_api_version_20250501, default: false)
      CopilotAPI::VERSION_2025_05_01
    else
      nil
    end
  end
end
