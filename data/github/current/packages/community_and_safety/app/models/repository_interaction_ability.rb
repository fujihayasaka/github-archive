# typed: true
# frozen_string_literal: true

class RepositoryInteractionAbility
  include Instrumentation::Model

  # The number of hours a user had to have been created before to be considered
  # a sockpuppet.
  TIME_LIMIT_HOURS = 24

  # The possible interaction limits that can be enabled. These should each have
  # `#{name}_enabled?` and `self.#{name}_enabled?` methods defined in this class.
  #
  # Should be kept in sync with the limit enum in the InteractionLimit model.
  INTERACTION_LIMITS = [:sockpuppet_disallowed, :contributors_only, :collaborators_only]

  DURATION_OPTIONS = {
    one_day: {
      duration: 1.day,
      value: 1,
      unit: "DAY",
      key: "ONE_DAY",
      text: "24 hours",
    },
    three_days: {
      duration: 3.days,
      value: 3,
      unit: "DAY",
      key: "THREE_DAYS",
      text: "3 days",
    },
    one_week: {
      duration: 1.week,
      value: 1,
      unit: "WEEK",
      key: "ONE_WEEK",
      text: "1 week",
    },
    one_month: {
      duration: 1.month,
      value: 1,
      unit: "MONTH",
      key: "ONE_MONTH",
      text: "1 month",
    },
    six_months: {
      duration: 6.months,
      value: 6,
      unit: "MONTH",
      key: "SIX_MONTHS",
      text: "6 months",
    },
  }

  DURATION_AUDIT_LOG_MAPPING = {
    0 => :one_day,
    1 => :three_days,
    2 => :one_week,
    3 => :one_month,
    4 => :six_months,
  }

  attr_reader :object

  def self.restricted_message(type, action)
    case type
    when "existing_users"
      "An owner of this repository has limited the ability to #{action} from new users."
    when "contributors"
      "An owner of this repository has limited the ability to #{action} to users that have contributed to this repository in the past."
    when "collaborators"
      "An owner of this repository has limited the ability to #{action} to users that are collaborators on this repository."
    when "blocked"
      "Your ability to #{action} in this repository is currently blocked. If you feel this is in error, please contact the repository's owner."
    else nil
    end
  end

  def self.interaction_ban_copy(repo, user, action = "comment", tooltip = false)
    self.async_interaction_ban_copy(repo, user, action, tooltip).sync
  end

  def self.async_interaction_ban_copy(repo, user, action = "comment", tooltip = false)
    self.async_restricted_by_limit?(:sockpuppet_disallowed, repo, user).then do |is_restricted|
      next self.restricted_message("existing_users", action) if is_restricted

      self.async_restricted_by_limit?(:contributors_only, repo, user).then do |is_restricted|
        next self.restricted_message("contributors", action) if is_restricted

        self.async_restricted_by_limit?(:collaborators_only, repo, user).then do |is_restricted|
          next self.restricted_message("collaborators", action) if is_restricted

          next self.restricted_message("blocked", action) if self.blocked?(repo, user)

          user.async_user_interaction_limit.then do |limit|
            result = []
            result << "Your ability to #{action} has been suspended"
            ban_expiry = limit&.expiry
            if ban_expiry
              result << " for #{ActionController::Base.helpers.distance_of_time_in_words(DateTime.now, ban_expiry)}"
            end
            result << "."

            unless tooltip
              result << " If you feel this is in error, please "
              result << ActionController::Base.helpers.link_to(
                "contact GitHub support",
                Rails.application.routes.url_helpers.contact_path(form: { subject: "Interaction ability suspended" })
              )
              result << "."
            end

            ActionController::Base.helpers.safe_join(result)
          end
        end
      end
    end
  end

  # Public: Checks if the sockpuppet disallowed limit is enabled, which prevents newer
  # accounts from interacting with a repository.
  #
  # object - The Repository, User, or Organization that you are checking.
  #
  # Returns a Boolean.
  def self.sockpuppet_disallowed_enabled?(object)
    async_sockpuppet_disallowed_enabled?(object).sync
  end

  def self.async_sockpuppet_disallowed_enabled?(object)
    new(object).async_sockpuppet_disallowed_enabled?
  end

  # Public: Checks if the contributors only limit is enabled, which ensures that
  # only prior contributors can interact with a repository.
  #
  # object - The Repository, User, or Organization that you are checking.
  #
  # Returns a Boolean.
  def self.contributors_only_enabled?(object)
    async_contributors_only_enabled?(object).sync
  end

  def self.async_contributors_only_enabled?(object)
    new(object).async_contributors_only_enabled?
  end

  # Public: Checks if the collaborators only limit is enabled, which ensures that
  # only collaborators can interact with a repository.
  #
  # object - The Repository, User, or Organization that you are checking.
  #
  # Returns a Boolean.
  def self.collaborators_only_enabled?(object)
    async_collaborators_only_enabled?(object).sync
  end

  def self.async_collaborators_only_enabled?(object)
    new(object).async_collaborators_only_enabled?
  end

  # Public: Checks if a user is able to interact with a repository.
  #
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Promise<Boolean>.
  def self.async_interaction_allowed?(repository:, user:)
    return Promise.resolve(false) unless repository.present?
    return Promise.resolve(false) unless user.present?

    ability = new(repository)

    ability.async_overall_active_limit.then do |active_limit|
      if active_limit == :no_limit
        GitHub.dogstats.increment("repo_interaction_limit.check_interaction_allowed", tags: ["limit:#{active_limit}"])
        next true
      end

      async_user_exempt?(active_limit, repository, user).then do |is_exempt|
        GitHub.dogstats.increment("repo_interaction_limit.check_interaction_allowed", tags: ["limit:#{active_limit}", "exempt:#{is_exempt}"])
        is_exempt
      end
    end
  end

  # Public: Check if a limit should restrict a user from interacting with a repository.
  #
  # limit      - A Symbol interaction limit name; one of INTERACTION_LIMITS
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Boolean.
  def self.restricted_by_limit?(limit, repository, user)
    async_restricted_by_limit?(limit, repository, user).sync
  end

  def self.async_restricted_by_limit?(limit, repository, user)
    raise ArgumentError, "Expected limit to be one of #{INTERACTION_LIMITS}, was #{limit}" unless INTERACTION_LIMITS.include?(limit)

    return Promise.resolve(false) if repository.private?

    ability = new(repository)

    ability.async_overall_active_limit.then do |active_limit|
      next false unless active_limit == limit

      async_user_exempt?(limit, repository, user).then do |is_exempt|
        !is_exempt
      end
    end
  end

  # Public: Check if an interaction limit doesn't apply to a user.
  #
  # limit      - A Symbol interaction limit name; one of INTERACTION_LIMITS
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Boolean.
  def self.user_exempt?(limit, repository, user)
    async_user_exempt?(limit, repository, user).sync
  end

  # Public: Check if an interaction limit doesn't apply to a user.
  #
  # limit      - A Symbol interaction limit name; one of INTERACTION_LIMITS
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Promise<Boolean>.
  def self.async_user_exempt?(limit, repository, user)
    raise ArgumentError, "Expected limit to be one of #{INTERACTION_LIMITS}, was #{limit.inspect}" unless INTERACTION_LIMITS.include?(limit)

    case limit
    when :sockpuppet_disallowed
      async_user_exempt_from_sockpuppet_allowed?(
        repository: repository,
        user: user,
      )
    when :contributors_only
      async_user_exempt_from_contributors_only?(
        repository: repository,
        user: user,
      )
    when :collaborators_only
      async_user_exempt_from_collaborators_only?(
        repository: repository,
        user: user,
      )
    end
  end

  # Public: Check if a user is blocked in a repository
  #
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Boolean.
  def self.blocked?(repository, user)
    repository.owner_blocking?(user)
  end

  # Private: Check if the sockpuppet_disallowed limit doesn't apply to a user.
  #
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Promise<Boolean>.
  def self.async_user_exempt_from_sockpuppet_allowed?(repository:, user:)
    return Promise.resolve(true) unless user.user?

    async_user_recently_created?(user).then do |recently_created|
      next true unless recently_created

      # if exempt from a higher limit, they are exempt from this one too
      async_user_exempt_from_contributors_only?(repository: repository, user: user)
    end
  end
  private_class_method :async_user_exempt_from_sockpuppet_allowed?

  # Private: Check if the contributors_only limit doesn't apply to a user.
  #
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Promise<Boolean>.
  def self.async_user_exempt_from_contributors_only?(repository:, user:)
    return Promise.resolve(true) unless user.user?

    repository.async_contributor?(user).then do |is_contributor|
      next true if is_contributor

      # if exempt from a higher limit, they are exempt from this one too
      async_user_exempt_from_collaborators_only?(repository: repository, user: user)
    end
  end
  private_class_method :async_user_exempt_from_contributors_only?

  # Private: Check if the collaborators_only limit doesn't apply to a user.
  #
  # repository - The Repository a user is interacting with.
  # user       - The User that is interacting with the repository.
  #
  # Returns a Promise<Boolean>.
  def self.async_user_exempt_from_collaborators_only?(repository:, user:)
    return Promise.resolve(true) unless user.user?

    repository.async_pushable_by?(user).then do |is_pushable|
      next true if is_pushable

      repository.async_member?(user).then do |is_collaborator|
        next true if is_collaborator
        async_member_of_org?(repository, user)
      end
    end
  end
  private_class_method :async_user_exempt_from_collaborators_only?

  # Public: Disable any currently active interaction limit for an object.
  #
  # object - The Repository, User, or Organization to disable interaction limits for.
  # actor  - The User disabling the interaction limits.
  # staff_actor - A Boolean indicating if audit log events should guard the
  #               actor's identity, and log the `github-staff` account instead.
  #
  # Returns nothing.
  def self.disable_active_local_limit_for(object, actor = User.staff_user, staff_actor: false)
    new(object).disable_active_local_limit(actor, staff_actor: staff_actor)
  end

  # Public: Disables any currently active local interaction limit for
  #         the current object.
  #         NOTE: This should only be called for automated
  #         operations – for regular users who want to disable a specific limit,
  #         please use `set_ability` with `:no_limit` as the limit.
  #
  # actor  - The User disabling the interaction limits.
  # staff_actor - A Boolean indicating if audit log events should guard the
  #               actor's identity, and log the `github-staff` account instead.
  #
  # Returns nothing.
  def disable_active_local_limit(actor, staff_actor: false)
    active_limit = local_active_limit
    return if active_limit == :no_limit

    GitHub.dogstats.increment("repo_interaction_limit.disable_active_local_limit")
    object.disable_repo_interaction_limit
    object.reset_repo_interaction_limit

    instrument_update(
      limit: active_limit,
      action: :disable,
      actor: actor,
      staff_actor: staff_actor
    )

    true
  end

  # Public: Check if an object has any limits currently enabled.
  #
  # object - The Repository, User, or Organization that you are checking.
  #
  # Returns a Boolean.
  def self.has_active_limits?(object)
    async_has_active_limits?(object).sync
  end

  def self.async_has_active_limits?(object)
    ability = new(object)

    return Promise.resolve(false) if ability.repository? && object.private?

    ability.async_overall_active_limit.then do |limit|
      limit != :no_limit
    end
  end

  # Public: Initialize a RepositoryInteractionAbility instance.
  #
  # object - The Repository, User, or Organization that you are checking.
  def initialize(object)
    @object = object
  end

  # Public: Checks if the sockpuppet disallowed limit is enabled.
  #
  # Returns a Boolean.
  def sockpuppet_disallowed_enabled?
    async_sockpuppet_disallowed_enabled?.sync
  end

  def async_sockpuppet_disallowed_enabled?
    async_limit_enabled?(:sockpuppet_disallowed)
  end

  # Public: Checks if the contributors only limit is enabled.
  #
  # Returns a Boolean.
  def contributors_only_enabled?
    async_contributors_only_enabled?.sync
  end

  def async_contributors_only_enabled?
    async_limit_enabled?(:contributors_only)
  end

  # Public: Checks if the collaborators only limit is enabled.
  #
  # Returns a Boolean.
  def collaborators_only_enabled?
    async_collaborators_only_enabled?.sync
  end

  def async_collaborators_only_enabled?
    async_limit_enabled?(:collaborators_only)
  end

  # Public: The active InteractionLimit for this object.
  def async_load_active_limit(scope: :overall)
    Platform::Loaders::RepositoryInteractionLimit.load(object, scope).then do |limit|
      GitHub.dogstats.increment("repo_interaction_limit.load_active_limit", tags: ["limit:#{limit.restriction}", "origin:#{limit.origin}"]) if limit

      limit
    end
  end

  # Public: The current limit that is active for this object.
  #
  # Returns a Promise<Symbol>.
  def async_local_active_limit
    async_load_active_limit(scope: :local).then do |active_limit|
      next :no_limit unless active_limit

      active_limit.restriction
    end
  end

  # Public: The current limit that is active for this object.
  #
  # Returns a Symbol.
  def local_active_limit
    async_local_active_limit.sync
  end

  # Public: The current limit, either at the repo or org level, that is active
  # for this object.
  #
  # For a repo, this will be the owner's limit if it exists, or the repo's local
  # limit otherwise.
  #
  # Returns a Promise<Symbol>.
  def async_overall_active_limit
    async_load_active_limit.then do |active_limit|
      next :no_limit unless active_limit

      active_limit.restriction
    end
  end

  # Public: The current limit, either at the repo or user level, that is active
  #         for this object.
  #
  # Returns a Symbol.
  def overall_active_limit
    async_overall_active_limit.sync
  end

  # Public: The origin of the currently active limit.
  #
  # Returns a Promise<Symbol>.
  def async_active_limit_origin
    return Promise.resolve(:organization) if organization?
    return Promise.resolve(:user) if user?

    async_load_active_limit.then do |limit|
      next :repository unless limit&.overall?

      limit.async_user.then do
        limit.origin
      end
    end
  end

  # Public: The origin of the currently active limit.
  #
  # Returns a Symbol.
  def active_limit_origin
    async_active_limit_origin.sync
  end

  # Public: Does this object have an active overall limit?
  #
  # Returns a Promise<Boolean>.
  def async_has_overall_limit?
    return Promise.resolve(false) unless repository?

    async_load_active_limit.then do |limit|
      limit&.overall? || false
    end
  end

  # Public: Does this object have an active overall limit?
  #
  # Returns a Boolean.
  def has_overall_limit?
    async_has_overall_limit?.sync
  end

  # Public: Get the currently enabled overall limit's expiration.
  #
  # Returns a Promise<DateTime | nil>.
  def async_overall_active_limit_expiry
    async_load_active_limit.then do |limit|
      limit.expiry if limit
    end
  end

  # Public: Get the currently enabled overall limit's expiration.
  #
  # Returns a DateTime|nil.
  def overall_active_limit_expiry
    async_overall_active_limit_expiry.sync
  end

  # Public: Get the currently enabled interaction limit's expiration.
  #
  # Returns a Promise<DateTime | nil>.
  def async_local_active_limit_expiry
    async_load_active_limit(scope: :local).then do |limit|
      limit.expiry if limit
    end
  end

  # Public: Get the currently enabled interaction limit's expiration.
  #
  # Returns a Boolean.
  def local_active_limit_expiry
    async_local_active_limit_expiry.sync
  end

  # Public: Sets an interaction limit.
  #
  # limit - A Symbol interaction limit name; one of INTERACTION_LIMITS
  # actor - The User setting this interaction limit.
  # duration - When the interaction limit should expire; one of the keys of DURATION_OPTIONS.
  # staff_actor - A Boolean indicating if audit log events should guard the
  # actor's identity, and log the `github-staff` account instead.
  #
  # Returns a Boolean.
  def set_ability(limit, actor, duration = DURATION_OPTIONS.keys.first, staff_actor: false)
    if repository?
      # Don't allow enabling repo level limits if an overall interaction
      # limit is already enabled.
      return false if self.class.has_active_limits?(object.owner)
    end

    current_limit = local_active_limit

    # return early if you're trying to disable the current limit, but there isn't one
    return true if limit == :no_limit && current_limit == :no_limit

    already_enabled = limit == local_active_limit

    # Disable any existing limits before enabling a new limit.
    # Only one limit should be enabled at a time.
    unless already_enabled
      disable_active_local_limit(actor, staff_actor: staff_actor)
    end

    # Return early if we just needed to disable all limits.
    return true if limit == :no_limit

    GitHub.dogstats.increment("repo_interaction_limit.set_ability", tags: ["limit:#{limit}", "duration:#{duration}"])
    expires_at = DURATION_OPTIONS[duration][:duration].from_now
    object.enable_repo_interaction_limit(restriction: limit, expires_at: expires_at)
    object.reset_repo_interaction_limit

    if !repository? && !already_enabled
      # Disable repository-level interaction limits for public repositories
      # since the overall limit is set instead.
      DisableRepositoryInteractionLimitsJob.perform_later(object.id, actor.id)
    end

    instrument_update(
      limit: limit,
      action: :enable,
      duration: duration,
      actor: actor,
      staff_actor: staff_actor
    )

    true
  end

  # Public: Is the current interaction ability instance for an organization?
  #
  # Returns a Boolean.
  def organization?
    object.is_a?(Organization)
  end

  # Public: Is the current interaction ability instance for a user?
  #
  # Returns a Boolean.
  def user?
    # Organizations are users, so let's make sure we're explicit here
    return false if organization?
    object.is_a?(User)
  end

  # Public: Is the current interaction ability instance for a repository?
  #
  # Returns a Boolean.
  def repository?
    object.is_a?(Repository)
  end

  # Private: Was this user created within the the sockpuppet timeframe?
  #
  # user - the User to check.
  #
  # Returns a Promise<Boolean>.
  sig { params(user: User).returns(Promise[T::Boolean]) }
  def self.async_user_recently_created?(user)
    Promise.resolve((Time.now - T.must(user.created_at)).to_i / 1.hour < TIME_LIMIT_HOURS)
  end
  private_class_method :async_user_recently_created?

  # Private: For org repos, is a user a Member of the org?
  #
  # repository - the org repo to check.
  # user - the User to check.
  #
  # Returns a Promise<Boolean>.
  def self.async_member_of_org?(repository, user)
    repository.async_in_organization?.then do |in_organization|
      next false unless in_organization

      repository.async_organization.then do |org|
        org.async_member?(user)
      end
    end
  end
  private_class_method :async_member_of_org?

  private

  # Private: The event prefix used for audit log events.
  #
  # Returns a String.
  def event_prefix
    return "user" if user?

    prefix = organization? ? "org" : "repo"
    "#{prefix}.config"
  end

  # Private: Checks to see if a limit is enabled.
  #
  # limit - A Symbol interaction limit name; one of INTERACTION_LIMITS
  #
  # Returns a Boolean.
  def limit_enabled?(limit)
    async_limit_enabled?(limit).sync
  end

  def async_limit_enabled?(limit)
    async_local_active_limit.then do |active_limit|
      active_limit == limit
    end
  end

  # Private: The tags to use when logging DataDog stats.
  #
  # Returns an Array.
  def stats_tags
    if user?
      ["type:user"]
    elsif organization?
      ["type:org"]
    else
      []
    end
  end

  # Private: Instrument the toggling of an interaction limit to the audit log,
  #          Hydro, and Datadog.
  #
  # limit – The Symbol interaction limit name that is being updated, one of INTERACTION_LIMITS.
  # action - The Symbol action being performed, either :enable or :disable.
  # duration – The Symbol duration that this limit is being enabled for, if it is being
  #            enabled. One of the keys from DURATION_OPTIONS.
  # actor - The User performing the action.
  # staff_actor - A Boolean indicating if audit log events should guard the
  #               actor's identity, and log the `github-staff` account instead.
  #
  # Returns nothing.
  def instrument_update(limit:, action:, duration: nil, actor:, staff_actor: false)
    audit_event = "#{action}_#{limit}"
    audit_context = object.event_context.merge({
      duration: DURATION_AUDIT_LOG_MAPPING.invert[duration]
    }.compact)

    if repository? && object.owner.organization?
      audit_context = audit_context.merge(object.owner.event_context)
    end

    if staff_actor
      guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      instrument audit_event, audit_context.merge(guarded_actor)
    else
      instrument audit_event, audit_context.merge({ actor: actor })
    end

    GitHub.dogstats.increment("#{limit}.#{action}", tags: stats_tags)

    GlobalInstrumenter.instrument("interaction_limit.update", {
      target_type: object.class,
      target_id: object.id,
      limit: limit,
      action: action,
      duration: duration,
      actor: actor,
      staff_actor: staff_actor,
    })
  end
end
