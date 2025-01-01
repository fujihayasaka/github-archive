# typed: true
# frozen_string_literal: true

module CopilotChatHelper
  extend T::Helpers
  include GitHub::Memoizer
  include AvatarHelper
  include FeatureFlagHelper

  FEATURE_FLAG_TO_PROMPTS = {
    copilot_showcase_icebreakers_include_whats_new: "whats-new-in-copilot",
    copilot_showcase_icebreakers_include_make_pong: "make-pong",
  }

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
  memoize def hide_site_header?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_no_header)
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
      repo_ci_json = Copilot::CustomInstructions.for_repository(repo, current_oid)
      if repo_ci_json
        custom_instructions.append(repo_ci_json)
      end
    end

    if repo.owner.is_a?(Organization)
      org_ci = Copilot::CustomInstructions.for_organization(T.cast(repo.owner, Organization))
      if org_ci
        custom_instructions.append(org_ci.as_json)
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
  def current_user_can_view_knowledge_bases?
    GitHub.dogstats.increment("copilot_chat_helper.current_user_can_view_knowledge_bases")
    GitHub.tracer.in_span("copilot_chat_helper.current_user_can_view_knowledge_bases") do |_span|
      copilot_user = current_copilot_user_v2
      return false unless copilot_user
      T.must(copilot_user).has_ce_access?
    end
  end

  sig { returns(T::Boolean) }
  memoize def opted_in_to_user_feedback?
    return false unless current_user

    T.must(current_copilot_user_v2).user_feedback_opt_in_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def repo_custom_instructions_enabled?
    copilot_user = T.must(current_copilot_user_v2)
    # the user has free/individual access || the user is opted in to preview features
    copilot_user.has_ci_access? || copilot_user.beta_features_github_chat_enabled?
  end

  # This is a temporary duplicate of packages/copilot_spaces/app/lib/custom_copilots/feature_preview_redirect.rb's
  # copilot_spaces_enabled? method.
  sig { returns(T::Boolean) }
  memoize def copilot_spaces_enabled?
    # Custom copilots are enabled for:
    # 1. users with the :copilot_custom_copilots feature flag, which some will be individually opted into
    # 2. The following types of users with the :copilot_custom_copilots_feature_preview feature flag:
    #    a. users with Copilot Individual (CI) licenses, for whom preview features are always enabled
    #    b. CB and CE users whose orgs have opted into preview features
    #    c. Copilot Free users, signified by `has_limited_access` on their plan
    feature_enabled_globally_or_for_user?(feature_name: :copilot_custom_copilots) ||
      (feature_enabled_globally_or_for_user?(feature_name: :copilot_custom_copilots_feature_preview) &&
      (current_copilot_user_v2&.beta_features_github_chat_enabled? || current_copilot_user_v2&.has_limited_access?))
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

    encrypted = simple_box.encrypt(token)

    # The encrypted token gets passed around to the browser and ultimately into an HTTP header in requests to CAPI,
    # so it needs to be URL encoded/decoded.
    encoded = Base64.urlsafe_encode64(encrypted)

    Copilot::EncryptedToken.from(encoded, expiration: new_access.expires_at)
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
    user = T.must(current_user)
    copilot_user = T.must(current_copilot_user_v2)
    org_ids = authorized_organizations.map { |org| org[:id] }

    {
      agentsPath: Rails.application.routes.url_helpers.copilot_chat_agents_path,
      apiURL: copilot_api_url,
      currentUserLogin: current_user&.display_login,
      customInstructions: get_default_custom_instructions(org_ids, T.must(current_user)).as_json,
      renderKnowledgeBases: current_user_can_view_knowledge_bases?,
      customCopilotsEnabled: copilot_spaces_enabled?,
      optedInToPreviewFeatures: copilot_user.beta_features_github_chat_enabled?,
      optedInToUserFeedback: opted_in_to_user_feedback?,
      renderAttachKnowledgeBaseHerePopover: !user.dismissed_notice?(:copilot_for_docs_attach_knowledge_base_here),
      renderKnowledgeBaseAttachedToChatPopover: !user.dismissed_notice?(:copilot_for_docs_knowledge_base_attached_to_chat),
      personalInstructions: Copilot::CustomInstructions.where(owner_type: "User", owner_id: user.id).first&.prompt,
      renderBetaLabel: render_beta_label?,
      reviewLab: GitHub.review_lab?,
      realIp: Rails.env.development? ? T.must(request).remote_ip : nil,
      scrollToTop: scroll_copilot_to_top,
      hasCEorCBAccess: (copilot_user.has_ce_access? || copilot_user.has_cb_access?),
      licenseType: license_type,
      plan: feature_enabled_globally_or_for_user?(feature_name: :copilot_premium_request_quotas) ? user_plan : nil,
      quotas: user_quotas,
      icebreakers: get_icebreakers_json,
      canShareThread: CopilotPLG.domain.user_can_share_copilot_thread?(current_user),
      thirdPartyMcpAllowed: copilot_user.mcp_enabled?,
    }
  end

  memoize def license_type
    copilot_user = T.must(current_copilot_user_v2)

    return "unlicensed" unless copilot_user.has_copilot_access?

    copilot_user.has_limited_access? ? "licensed_limited" : "licensed_full"
  end

  memoize def user_plan
    copilot_user = T.must(current_copilot_user_v2)
    return nil unless copilot_user.has_copilot_access? || !feature_enabled_globally_or_for_user?(feature_name: :copilot_premium_request_quotas)

    return "free" if copilot_user.has_limited_access?
    return "pro" if copilot_user.has_pro_access?
    return "pro_plus" if copilot_user.has_pro_plus_access?
    return "max" if copilot_user.has_max_access?
    return "enterprise" if copilot_user.has_ce_access? # order is important here since enterprise users also have business access
    "business" if copilot_user.has_cb_access?
  end

  memoize def user_quotas
    copilot_user = T.must(current_copilot_user_v2)
    return nil unless copilot_user.has_limited_access? || feature_enabled_globally_or_for_user?(feature_name: "copilot_premium_request_quotas")

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

    {
      limits: limits,
      remaining: remaining,
      resetDate: copilot_user.quota_reset_date,
      overagesEnabled: copilot_user.overages_enabled?,
    }
  end

  memoize def user_trial
    copilot_user = T.must(current_copilot_user_v2)
    return nil unless feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_include_trial_details)
    return nil unless copilot_user.has_copilot_access?

    result = { eligible: copilot_user.eligible_for_trial? }
    result[:daysLeft] = copilot_user.days_left_on_trial if copilot_user.has_trial_access?
    result
  end

  sig { returns(String) }
  memoize def copilot_api_url
    Copilot::SKUIsolation.for_user(current_user).api.endpoint
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

  # Show Spark dashboard entrypoints. Using the same logic as Copilot chat for now.
  sig { returns(T::Boolean) }
  memoize def show_spark_entrypoint?
    return false unless current_user
    return false unless T.must(current_user).spark_enabled?

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
    return false unless current_copilot_user_v2
    !T.must(current_copilot_user_v2).show_copilot_functionality?
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
end
