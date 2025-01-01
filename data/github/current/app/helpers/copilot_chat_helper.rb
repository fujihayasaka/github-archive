# typed: true
# frozen_string_literal: true

module CopilotChatHelper
  extend T::Helpers
  include GitHub::Memoizer
  include AvatarHelper
  include FeatureFlagHelper

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

    custom_instructions = []

    if repo_custom_instructions_enabled?
      repo_ci = Copilot::CustomInstructions.for_repository(repo, current_oid)
      if repo_ci
        custom_instructions.append({
          type: :Repository,
          prompt: repo_ci
        })
      end
    end

    if T.must(current_user).feature_preview_enabled?(:copilot_chat_custom_instructions) && repo.owner.is_a?(Organization)
      org_ci = Copilot::CustomInstructions.for_organization(T.cast(repo.owner, Organization))
      if org_ci
        custom_instructions.append({
          type: :Organization,
          prompt: org_ci.prompt
        })
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
    # is the main feature flag enabled ||
    # (the preview flag enabled && (the user has free/individual access || the user is opted in to preview features))
    feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_repo_custom_instructions) ||
      (feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_repo_custom_instructions_preview) &&
      (copilot_user.has_ci_access? || copilot_user.beta_features_github_chat_enabled?))
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

  def integration_url(integration)
    if Integration.not_in_marketplace.where(id: integration.id).count == 0
      T.unsafe(self).marketplace_listing_path(integration.slug)
    else
      T.unsafe(self).gh_app_path(integration, current_user)
    end
  end

  def copilot_chat_payload(scroll_copilot_to_top = false, authorized_organizations = [], request = nil)
    user = T.must(current_user)
    copilot_user = T.must(current_copilot_user_v2)
    org_ids = authorized_organizations.map { |org| org[:id] }

    {
      agentsPath: Rails.application.routes.url_helpers.copilot_chat_agents_path,
      apiURL: copilot_api_url,
      currentUserLogin: current_user&.display_login,
      customInstructions: get_default_custom_instructions(org_ids, T.must(current_user))&.prompt || "",
      renderKnowledgeBases: current_user_can_view_knowledge_bases?,
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
      quotas: limited_user_quotas,
      icebreakers: get_icebreakers_json,
      canShareThread: CopilotPLG.domain.user_can_share_copilot_thread?(current_user),
    }
  end

  memoize def license_type
    copilot_user = T.must(current_copilot_user_v2)

    return "unlicensed" unless copilot_user.has_copilot_access?

    copilot_user.has_limited_access? ? "licensed_limited" : "licensed_full"
  end

  memoize def limited_user_quotas
    copilot_user = T.must(current_copilot_user_v2)
    return nil unless copilot_user.has_limited_access?

    limited_user = Copilot::LimitedUser.for_subscribed_user(T.must(current_user))

    return nil unless limited_user

    {
      limits: Copilot::Quotas.monthly_quotas,
      remaining: limited_user.quotas_remaining,
      resetDate: limited_user.reset_date
    }
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
    return true if unlicensed_and_unblocked_user?

    copilot_chat_enabled_for_current_user?
  end

  # Show Spark dashboard entrypoints. Using the same logic as Copilot chat for now.
  sig { returns(T::Boolean) }
  memoize def show_spark_entrypoint?
    return false unless current_user
    return false unless T.must(current_user).feature_enabled?(:spark_dashboard)

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
    return false if current_user&.feature_enabled?(:copilot_chat_dotcom_ga)
    !current_copilot_user_v2&.has_ce_access?
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def get_icebreakers_json
    file_path = Rails.root.join("config/copilot-icebreakers.json")
    data = JSON.parse(File.read(file_path))
    [
      { type: "functional", data: data["functional"] || [] },
      { type: "instructional", data: data["instructional"] || [] },
      { type: "interactional", data: data["interactional"] || [] }
    ]
  end

  sig { params(num_icebreakers: Integer).returns(T::Array[T.untyped]) }
  def get_icebreakers(num_icebreakers)
    file_path = Rails.root.join("config/copilot-icebreakers.json")
    icebreakers = JSON.parse(File.read(file_path))
    functional_icebreakers = icebreakers["functional"] || []
    instructional_icebreakers = icebreakers["instructional"] || []
    functional_icebreakers.concat(instructional_icebreakers).sample(num_icebreakers)
  end

  sig { params(org_ids: T::Array[Integer], user: User).returns(T.nilable(Copilot::CustomInstructions)) }
  def get_default_custom_instructions(org_ids, user)
    default_org_id = user.settings.get(:copilot_default_org_custom_instructions)

    custom_instructions = user.feature_preview_enabled?(:copilot_chat_custom_instructions) ? get_custom_instructions(org_ids) : []

    # if the user did not specify a default org, we return the first available custom instructions
    custom_instructions.find { |ci| ci.owner.id == default_org_id } || custom_instructions.first
  end

  sig { params(org_ids: T::Array[Integer]).returns(T::Array[Copilot::CustomInstructions]) }
  def get_custom_instructions(org_ids)
    user = T.must(current_user)
    return [] unless user.feature_preview_enabled?(:copilot_chat_custom_instructions)

    custom_instructions = Copilot::CustomInstructions.where(owner_id: org_ids, owner_type: "Organization").includes(:owner)

    custom_instructions.filter do |custom_instructions|
      custom_instructions.prompt.present? && Copilot::Organization.new(custom_instructions.owner).can_use_copilot_enterprise_features?
    end
  end
end
