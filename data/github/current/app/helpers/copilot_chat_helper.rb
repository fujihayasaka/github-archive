# typed: true
# frozen_string_literal: true

module CopilotChatHelper
  extend T::Sig
  extend T::Helpers
  include GitHub::Memoizer
  include AvatarHelper
  include FeatureFlagHelper

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(Copilot::User)) }
  def current_copilot_user; end

  class CopilotChatAuthError < StandardError; end

  # A user is enabled for copilot dotcom chat if:
  # 1. The copilot_dotcom_chat feature flag is enabled for the user or globally
  # 2. The user has CFB access AND their org admin has enabled it.
  # 3. That's it.
  sig { returns(T::Boolean) }
  memoize def copilot_chat_enabled_for_current_user?
    GitHub.dogstats.increment("copilot_chat_helper.copilot_chat_enabled_for_current_user")
    GitHub.tracer.in_span("copilot_chat_helper.copilot_chat_enabled_for_current_user") do |_span|
      # if we don't have copilot, we can't have chat
      T.cast(GitHub.copilot_enabled?, T::Boolean) &&
      # the circuit breaker - if this is disabled, that means we turned it off and no one gets dotcom chat
      copilot_flag_enabled? &&
      # this checks if we're checking (copilot_conversational_ux_license_check being enabled means we ARE checking)
      # if we are checking, they have to have a seat or seat assignment
      copilot_chat_licensed_for_current_user? &&
      # if we're checking, that means we need to check their organization settings
      dotcom_chat_enabled_for_current_user?
    end
  end

  sig { params(repo: T.nilable(Repository), ref_name: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def repo_props(repo:, ref_name: nil)
    return if repo.blank?

    ref_name ||= repo.default_branch
    ref = repo.refs.find(ref_name)

    current_oid = if ref
      ref.target_oid
    elsif GitRPC::Util.valid_full_sha1?(ref_name)
      ref_name
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
    }
  end

  sig { returns(T::Boolean) }
  def copilot_flag_enabled?
    # this is a circuit breaker. if it is NOT enabled, we don't try checking stuff
    feature_enabled_globally_or_for_user?(feature_name: :copilot_dotcom_chat)
  end

  def copilot_rails_anchor_flag_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_rails_anchor)
  end

  sig { returns(T::Boolean) }
  def copilot_floating_button_flag_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_floating_button)
  end

  sig { returns(T::Boolean) }
  def copilot_chat_licensed_for_current_user?
    GitHub.dogstats.increment("copilot_chat_helper.copilot_chat_licensed_for_current_user")
    GitHub.tracer.in_span("copilot_chat_helper.copilot_chat_licensed_for_current_user") do |_span|
      # we're checking a user. if they aren't here, what are we doing?
      return false unless current_user

      # if the copilot_conversational_ux_license_check is shipped for everyone or just this user, we'll check their license
      # otherwise, it's free dotcom chat time!
      return true unless feature_enabled_globally_or_for_user?(feature_name: :copilot_conversational_ux_license_check)
      user_has_copilot_seat || user_has_copilot_seat_assignment
    end
  end

  sig { returns(T::Boolean) }
  def dotcom_chat_enabled_for_current_user?
    GitHub.dogstats.increment("copilot_chat_helper.dotcom_chat_enabled_for_current_user")
    GitHub.tracer.in_span("copilot_chat_helper.dotcom_chat_enabled_for_current_user") do |_span|
      copilot_user = current_copilot_user
      return false unless copilot_user
      T.must(copilot_user).dotcom_chat_enabled? && T.must(copilot_user).has_copilot_enterprise_access?
    end
  end

  sig { returns(T::Boolean) }
  def current_user_can_view_knowledge_bases?
    GitHub.dogstats.increment("copilot_chat_helper.current_user_can_view_knowledge_bases")
    GitHub.tracer.in_span("copilot_chat_helper.current_user_can_view_knowledge_bases") do |_span|
      copilot_user = current_copilot_user
      return false unless copilot_user
      T.must(copilot_user).has_cfe_access?
    end
  end

  sig { returns(T::Boolean) }
  memoize def user_has_copilot_seat
    GitHub.dogstats.increment("copilot_chat_helper.user_has_copilot_seat")
    GitHub.tracer.in_span("copilot_chat_helper.user_has_copilot_seat") do |_span|
      return false unless current_user
      Copilot::Seat.exists?(assigned_user_id: T.must(current_user).id)
    end
  end

  sig { params(accelerate: T::Boolean).returns(T::Boolean) }
  def user_has_copilot_seat_assignment(accelerate: false)
    GitHub.dogstats.increment("copilot_chat_helper.user_has_copilot_seat_assignment")
    GitHub.tracer.in_span("copilot_chat_helper.user_has_copilot_seat_assignment") do |_span|
      return false unless current_user

      has_seat_assignments = T.must(current_copilot_user).async_seat_assignments.sync.any?

      # if they have seat assignments and we're accelerating, we'll log it and queue the background job
      if accelerate && has_seat_assignments
        user_id = T.must(current_user).id
        GitHub.logger.info("Triggering seat assignment conversion", "gh.user.id" => user_id)

        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
          user_id: T.must(user_id),
        )
      end
      has_seat_assignments
    end
  end

  sig { returns(T::Boolean) }
  memoize def opted_in_to_user_feedback?
    return false unless current_user

    T.must(current_copilot_user).user_feedback_opt_in_enabled?
  end

  sig { returns(RbNaCl::SimpleBox) }
  memoize def simple_box
    T.must_because(GitHub.dotcom_capi_simple_box) { "must have an encryption key set" }
  end

  sig { params(user_session: UserSession).returns(Copilot::EncryptedToken) }
  def copilot_mint_token(user_session)
    user = T.must_because(user_session.user) { "we expect user_session to always have a user" }
    app = T.must_because(copilot_chat_app) { "copilot_chat_app should always be present" }

    new_access = app.grant(user, { user_session: user_session })

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
    ::Apps::Internal.integration(:copilot_chat)
  end

  def get_chat_agents(sso_organizations)
    get_integration_agents(sso_organizations).map do |agent|
      { name: agent.name, slug: agent.slug, avatarUrl: avatar_url_for(agent, 60), integrationUrl: integration_url(agent) }
    end
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

  def copilot_chat_payload
    user = T.must(current_user)
    {
      agentsPath: Rails.application.routes.url_helpers.copilot_chat_agents_path,
      apiURL: GitHub.copilot_api_url,
      currentUserLogin: current_user&.display_login,
      customInstructions: Copilot::CustomInstructions.visible_to_user(user),
      renderKnowledgeBases: user.feature_enabled?(:copilot_dotcom_chat_individual) ? current_user_can_view_knowledge_bases? : true,
      optedInToUserFeedback: opted_in_to_user_feedback?,
      renderAttachKnowledgeBaseHerePopover: !user.dismissed_notice?(:copilot_for_docs_attach_knowledge_base_here),
      renderKnowledgeBaseAttachedToChatPopover: !user.dismissed_notice?(:copilot_for_docs_knowledge_base_attached_to_chat),
      reviewLab: GitHub.review_lab?,
    }
  end
end
