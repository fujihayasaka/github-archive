# typed: true
# frozen_string_literal: true

# Defines context agnostic logic of the IP Allowlist conditional access policy.
module ConditionalAccess::Policy::IpAllowlist
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Object }

  # Computes applicability of this policy over N targets for conditional access
  #
  # targets - an Enumerable of targets for conditional access
  # target_provider - ConditionalAccess::TargetProvider to get target for conditional access
  #
  # Returns Array[targets] for which this policy is applicable
  def multiple_ip_allowlist_applicable(targets, target_provider)
    return [] unless GitHub.ip_allowlists_available?

    targets.filter do |target|
      next false if target == :no_target_for_conditional_access

      if target.class == User
        if applicable_user?(target, skip_user_level_enforcement_check: true)
          next true
        else
          next false
        end
      end

      [Platform::Models::Enterprise, Business, Organization].include?(target.class)
    end
  end

  # Computes satisfiability of this policy over N targets for conditional access
  #
  # targets - an Enumerable of targets for conditional access
  # target_provider - ConditionalAccess::TargetProvider to get target for conditional access
  #
  # Returns Array[targets] for which this policy is satisfied
  def multiple_ip_allowlist_satisfied(targets, target_provider)
    result = Hash.new { |h, k| h[k] = {} }
    targets.each do |target|
      satisfied = false

      if target.is_a?(Organization)
        @unauthorized_ip_allowlist_org_ids ||= unauthorized_ip_allowlist_org_ids
        satisfied = true unless @unauthorized_ip_allowlist_org_ids.include?(target.id)
      elsif target.is_a?(Business)
        @unauthorized_ip_allowlist_business_ids ||= unauthorized_ip_allowlist_business_ids
        satisfied = true unless @unauthorized_ip_allowlist_business_ids.include?(target.id)
      elsif target.class == User
        @unauthorized_ip_allowlist_user_ids ||= unauthorized_ip_allowlist_user_ids
        satisfied = true unless @unauthorized_ip_allowlist_user_ids.include?(target.id)
      else
        raise ArgumentError.new("unsupported target for conditional access")
      end

      result[target] = {
        "private": satisfied ? :satisfied : :unsatisfied,
      }
    end
    result
  end

  # Computes applicability of this policy for a target for conditional access. This method doesn't
  # check if the IP Allowlist conditional access policy is satisified for the given target though.
  # To check if the IP Allowlist CAP is satisified for the given target too, call the
  # ip_allowlist_satisfied method after this method.
  #
  # resource - Resource for conditional access
  # target_provider - ConditionalAccess::TargetProvider to get target for conditional access
  #
  # Returns Symbol
  def ip_allowlist_applicable(resource:, target_provider:)
    return :no unless GitHub.ip_allowlists_available?
    actor = get_actor
    return :no if actor.nil? && public_key.nil?

    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access

    if target.class == User
      if applicable_user?(target) && business_for_applicable_user(target).ip_allowlist_enabled?
        return :yes
      else
        return :no
      end
    end

    return :no unless [Platform::Models::Enterprise, Business, Organization].include?(target.class)
    return :no unless target.ip_allowlist_enabled?

    :yes
  end

  # Computes satisfiability of this policy for a target for conditional access. This method isn't
  # used independently, but rather with the ip_allowlist_applicable method, which first checks if
  # the IP Allowlist conditional access policy is applicable for a given target.
  #
  # resource - Resource for conditional access
  # target_provider - ConditionalAccess::TargetProvider to get target for conditional access
  #
  # Returns Symbol
  def ip_allowlist_satisfied(resource:, target_provider:)
    # Platform requests from specific internal services to internal API
    # service hosts are exempt from enforcement.
    return :yes if ip_allow_list_exempt_internal_api_request?

    actor = get_actor
    evaluate_ip_allowlist_satisfied(
      resource: resource,
      target_provider: target_provider,
      actor_ip: T.unsafe(self).actor_ip,
      actor: actor || public_key,
      repository: (resource if resource.is_a?(Repository)) || T.unsafe(self).repository,
      action: T.unsafe(self).callback.respond_to?(:action) ? T.unsafe(self).action : nil,
    )
  end

  private

  def get_actor
    T.unsafe(self).respond_to?(:true_actor) ? T.unsafe(self).true_actor : T.unsafe(self).actor
  end

  # Private: Is the given target a User where user-level IP allow list enforcement is applicable.
  #
  # target - The User to check.
  # skip_user_level_enforcement_check - Boolean indicating whether to skip checking whether the
  #   Business associated with the User has IP allow list user-level enforcement enabled.
  #   Defaults to false. Called with true when the check is not necessary for multiple applicability
  #   to avoid N+1s.
  #
  # Returns Boolean
  def applicable_user?(target, skip_user_level_enforcement_check: false)
    return false unless target.class == User
    return false unless target.is_enterprise_managed?

    if skip_user_level_enforcement_check
      true
    else
      target.enterprise_managed_business&.ip_allowlist_user_level_enforcement_enabled?
    end
  end

  # Private: Returns the Business where an IP allow list may be configured for an applicable User.
  #
  # Returns Business
  def business_for_applicable_user(user)
    user.enterprise_managed_business
  end

  # Private: Encapsulates logic to evaluate satisfiability, returning :yes or :no.
  #
  # Returns Symbol
  def evaluate_ip_allowlist_satisfied(resource:, target_provider:, actor_ip:, actor:, repository: nil, action: nil)
    actor_ip = actor_ip || GitHub.context[:actor_ip]

    # Public repositories are accessible when action is explicitly provided as :read
    return :yes if repository&.public? && action == :read
    evaluate_ip_allowlist_satisfied_debug_logging("passed repository&.public? && action == :read")

    # When an OAuth application owned by an Organization is identified by
    # client_id and client_secret the actor is also an Organization. In this
    # case skip all allow list checks when this actor is accessing public repositories.
    return :yes if actor.is_a?(OauthApplication) && actor.owner&.organization? && repository&.public?
    evaluate_ip_allowlist_satisfied_debug_logging("passed actor.respond_to?(:organization?) && actor.organization? && repository&.public?")

    if exempt_request_for_internal_app?(actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("returning because exempt_request_for_internal_app? is true")
      return :yes
    end
    evaluate_ip_allowlist_satisfied_debug_logging("passed exempt_request_for_internal_app?")

    # GitHub App actors
    if integration_actor?(actor)
      evaluate_ip_allowlist_satisfied_debug_logging("Started in integration_actor?")

      target = target_provider.target(resource)
      config_subject = target
      if applicable_user?(target)
        config_subject = business_for_applicable_user(target)
      end
      return :yes if config_subject.ip_allowlist_app_access_enabled? && allowed_for_subject?(subject: actor, actor_ip: actor_ip, actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("passed config_subject.ip_allowlist_app_access_enabled? && allowed_for_subject?")

      return :yes if allowed_for_subject?(subject: config_subject, actor_ip: actor_ip, actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject?")

      return unsatisfied(owner: target, actor: actor, actor_ip: actor_ip)
    end

    # GitHub App installation actors
    if (installation_actor = installation_actor(actor))
      evaluate_ip_allowlist_satisfied_debug_logging("passed if installation_actor = installation_actor")

      target = target_provider.target(resource)
      config_subject = target
      if applicable_user?(target)
        config_subject = business_for_applicable_user(target)
      end

      # Users cannot currently enable allow lists.
      # We only expect the installation target to return truthy for `#user?` if the
      # repository is a restricted private fork into a user account.
      return :yes if installation_actor.target&.user? && !repository&.ip_restricted_private_fork?
      evaluate_ip_allowlist_satisfied_debug_logging("passed installation_actor.target&.user? && !repository&.ip_restricted_private_fork?")

      if repository&.ip_restricted_private_fork?
        evaluate_ip_allowlist_satisfied_debug_logging("Started in repository&.ip_restricted_private_fork?")

        return :yes if allowed_for_subject?(
          subject: installation_actor.integration,
          actor_ip: actor_ip,
          actor: installation_actor
        )
        evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject? for installation_actor.integration subject")

        return :yes if allowed_for_subject?(
          subject: target,
          actor_ip: actor_ip,
          actor: installation_actor
        )
        evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject? for target subject")
      end

      return :yes if installation_actor.target_id == config_subject.id && (
        (
          config_subject.ip_allowlist_app_access_enabled? &&
          allowed_for_subject?(
            subject: installation_actor.integration,
            actor_ip: actor_ip,
            actor: installation_actor
          )
        ) ||
        allowed_for_subject?(subject: config_subject, actor_ip: actor_ip, actor: installation_actor)
      )

      # This installation is on an organization, the Business has IP allowlist configured.
      if installation_actor.target.is_a?(Organization) && config_subject.is_a?(Business) &&
        config_subject.feature_enabled?(:ip_allowlist_org_apps_access_business_target) &&
        config_subject.organization_ids.include?(installation_actor.target_id)
        evaluate_ip_allowlist_satisfied_debug_logging("passed config_subject.organization_ids.include?(installation_actor.target_id)")
        return :yes if (
          (
            config_subject.ip_allowlist_app_access_enabled? &&
            allowed_for_subject?(
              subject: installation_actor.integration,
              actor_ip: actor_ip,
              actor: installation_actor
            )
          ) ||
          allowed_for_subject?(subject: config_subject, actor_ip: actor_ip, actor: installation_actor)
        )
      end
      evaluate_ip_allowlist_satisfied_debug_logging("passed installation_actor.target_id == config_subject.id && ...")

      return unsatisfied(owner: target, actor: actor, actor_ip: actor_ip)
    end

    # Other actor types

    # Skip if other authz logic will prevent access to the resource
    target = target_provider.target(resource)
    evaluate_ip_allowlist_satisfied_debug_logging("Starting other actor types check")

    return :yes if skip_policy_evaluation_for_org?(actor: actor, owner: target, repository: repository)
    evaluate_ip_allowlist_satisfied_debug_logging("passed skip_policy_evaluation_for_org?")

    return :yes if skip_policy_evaluation_for_business_owned_org?(actor: actor, owner: target, repository: repository)
    evaluate_ip_allowlist_satisfied_debug_logging("passed skip_policy_evaluation_for_business_owned_org?")

    return :yes if skip_policy_evaluation_for_user?(actor: actor, owner: target, repository: repository)
    evaluate_ip_allowlist_satisfied_debug_logging("passed skip_policy_evaluation_for_user?")

    # Translation from config/policies/ip_allowlists.json:
    # https://github.com/github/authzd/blob/9068d53080f4d932dde92ce711e0b8d74a8f3119/config/policies/ip_allowlists.json#L62-L87
    if applicable_user?(target)
      evaluate_ip_allowlist_satisfied_debug_logging("Starting if applicable_user?(target)")

      config_subject = business_for_applicable_user(target)
      return :yes unless configured_for_subject?(config_subject)
      evaluate_ip_allowlist_satisfied_debug_logging("passed configured_for_subject?")

      return :yes if allowed_for_subject?(subject: config_subject, actor_ip: actor_ip, actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject?")

    elsif target.is_a?(Organization) && target.business.present?
      evaluate_ip_allowlist_satisfied_debug_logging("Starting elsif target.is_a?(Organization) && target.business.present?")

      return :yes if !configured_for_subject?(target.business) && !configured_for_subject?(target)
      evaluate_ip_allowlist_satisfied_debug_logging("passed !configured_for_subject?(target.business) && !configured_for_subject?(target)")

      return :yes if allowed_for_subject?(subject: target, actor_ip: actor_ip, actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject?(subject: target, actor_ip: actor_ip, actor: actor)")
    else
      evaluate_ip_allowlist_satisfied_debug_logging("Starting else")

      return :yes unless configured_for_subject?(target)
      evaluate_ip_allowlist_satisfied_debug_logging("passed unless configured_for_subject?(target)")

      return :yes if allowed_for_subject?(subject: target, actor_ip: actor_ip, actor: actor)
      evaluate_ip_allowlist_satisfied_debug_logging("passed allowed_for_subject?")
    end

    unsatisfied(owner: target, actor: actor, actor_ip: actor_ip)
  end

  def ip_allow_list_exempt_internal_api_request?
    T.unsafe(self).callback.respond_to?(:ip_allow_list_exempt_internal_api_request?) &&
    T.unsafe(self).callback.send(:ip_allow_list_exempt_internal_api_request?)
  end

  def configured_for_subject?(subject)
    IpAllowlistEntry.usable_for(subject).active.any?
  end

  def allowed_for_subject?(subject: nil, actor_ip: nil, actor: nil)
    return false unless subject

    GitHub.cache.fetch(cache_key(subject, actor_ip), ttl: 3.minutes) do
      IpAllowlistEntry.usable_for(subject).active.matching_ip(actor_ip).any?
    end
  end

  def cache_key(subject, actor_ip)
    ["cap-ip-allowlist", subject.class.name, subject.id, actor_ip].join(":")
  end

  def integration_actor?(actor)
    actor.is_a?(Integration)
  end

  def installation_actor?(actor)
    installation_actor(actor).present?
  end

  def installation_actor(actor)
    return unless actor.try(:can_have_granular_permissions?)
    installation_actor = actor.ability_delegate
    return unless installation_actor

    return unless installation_actor.respond_to?(:integration)
    return unless installation_actor.respond_to?(:target)

    installation_actor
  end

  def skip_policy_evaluation_for_user?(actor:, owner:, repository:)
    actor.is_a?(User) &&
    owner.class == User &&
    business_for_applicable_user(owner).present? &&
    !repository&.internal? &&
    (
      repository.present? &&
      !repository.readable_by?(actor)
    ) &&
    (
      repository_ids_for_actor(actor: actor).empty?
    )
  end

  def skip_policy_evaluation_for_org?(actor:, owner:, repository:)
    actor.is_a?(User) &&
    owner.is_a?(Organization) &&
    !owner.business.present? &&
    !repository&.internal? &&
    (
      (
        repository.present? &&
        !repository.readable_by?(actor)
      ) ||
      !owner.member?(actor)
    ) &&
    (
      repository_ids_for_actor(actor: actor).empty? ||
      !actor_outside_collaborator_for_organization?(actor: actor, owner: owner)
    )
  end

  def skip_policy_evaluation_for_business_owned_org?(actor:, owner:, repository:)
    actor.is_a?(User) &&
    owner.is_a?(Organization) &&
    owner.business.present? &&
    !repository&.internal? &&
    (
      (
        repository.present? &&
        !repository.readable_by?(actor)
      ) ||
      (
        member_policy_evaluation_for_business_owned_org?(actor: actor, owner: owner)
      )
    ) &&
    (
      repository_ids_for_actor(actor: actor).empty? ||
      !actor_outside_collaborator_for_organization?(actor: actor, owner: owner)
    )
  end

  def member_policy_evaluation_for_business_owned_org?(actor:, owner:)
    if owner.enterprise_managed_user_enabled?
      !owner.member?(actor) && owner.business != actor.enterprise_managed_business
    else
      !owner.member?(actor) && !actor.cap_enforcement_is_business_member?(owner.business&.id)
    end
  end

  def repository_ids_for_actor(actor:)
    return @repository_ids_for_actor if defined?(@repository_ids_for_actor)

    sql = Arel.sql <<-SQL, actor_id: actor.id
      SELECT subject_id
      FROM abilities
      WHERE priority   = 1
      AND actor_type   = 'User'
      AND actor_id     = :actor_id
      AND subject_type = 'Repository'
    SQL
    @repository_ids_for_actor = Ability.connection.select_values(sql).flatten.compact
  end

  def actor_outside_collaborator_for_organization?(actor:, owner:)
    return @actor_outside_collaborator_for_organization if defined?(@actor_outside_collaborator_for_organization)

    sql = Arel.sql <<-SQL, organization_id: owner.id, actor_repository_ids: repository_ids_for_actor(actor: actor)
      SELECT *
      FROM repositories
      WHERE active = 1
      AND organization_id = :organization_id
      AND id IN (:actor_repository_ids)
      LIMIT 1
    SQL

    @actor_outside_collaborator_for_organization = Repository.connection.select_value(sql).present?
  end

  # Apps on behalf of actors who don't take IP allow lists into consideration.
  #
  # These are internal apps that we have specifically designated with this
  # capability.
  def exempt_request_for_internal_app?(actor: nil)
    application = if actor.is_a?(Integration)
      actor
    elsif actor.is_a?(Bot) || actor.is_a?(SiteScopedIntegrationInstallation)
      actor.integration
    elsif actor.is_a?(GitAuth::SSHKey)
      nil
    else
      actor.respond_to?(:oauth_access) && actor&.oauth_access&.application
    end
    return false unless application.present?
    capable = Apps::Privileged.capable?(:ip_allowlist_exempt, app: application)
    evaluate_ip_allowlist_satisfied_debug_logging("Calculated capable", { "gh.is_capable" => capable })
    capable
  end

  def unsatisfied(owner:, actor:, actor_ip:)
    instrument_unsatisfied(owner: owner, actor: actor, actor_ip: actor_ip)
    :no
  end

  def instrument_unsatisfied(owner:, actor:, actor_ip:)
    payload = {
      owner: owner,
      actor_ip: actor_ip,
    }
    if integration_actor?(actor)
      payload[:integration_actor] = actor
    elsif !actor.is_a?(Bot) && installation_actor?(actor)
      payload[:integration_actor] = actor.integration
    elsif actor.is_a?(GitAuth::SSHKey)
      payload[:actor] = nil
    elsif actor.is_a?(OauthApplication)
      payload[:actor] = actor.owner
    else
      payload[:actor] = actor
    end
    GlobalInstrumenter.instrument("ip_allow_list.policy_unsatisfied", payload)
  end

  def public_key
    return nil unless T.unsafe(self).callback.respond_to?(:public_key)
    T.unsafe(self).callback.send(:public_key)
  end

  def unauthorized_ip_allowlist_org_ids
    ip_allowlist_authorization.protected_organization_ids
  end

  def unauthorized_ip_allowlist_business_ids
    ip_allowlist_authorization.protected_businesses.pluck(:id)
  end

  def unauthorized_ip_allowlist_user_ids
    ip_allowlist_authorization.protected_user_ids
  end

  def ip_allowlist_authorization
    return @ip_allowlist_authorization if defined?(@ip_allowlist_authorization)
    @ip_allowlist_authorization = Platform::Authorization::IpAllowlist.new( # rubocop:disable GitHub/DoNotInstantiatePlatformObjects
      user: T.unsafe(self).actor,
      ip: T.unsafe(self).actor_ip
    )
  end

  def evaluate_ip_allowlist_satisfied_debug_logging(msg, options = {})
    return unless GitHub.flipper[:evaluate_ip_allowlist_satisfied_debug_logging].enabled?
    GitHub.logger.info(
      msg,
      {
        "code.function": "evaluate_ip_allowlist_satisfied",
        "gh.request_id": GitHub.context[:request_id],
         **options
      }
    )
  end
end
