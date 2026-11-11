# typed: strict
# frozen_string_literal: true

class UserBypassActor < RepositoryRulesetBypassActor
  validate :check_for_repository_ruleset

  sig { returns(String) }
  def self.display_type
    "User"
  end

  sig { returns(String) }
  def self.display_name
    "User"
  end

  sig { returns(T.nilable(User)) }
  def user
    T.let(actor, T.nilable(User))
  end

  sig { returns(T.nilable(String)) }
  def actor_global_relay_id
    user&.global_relay_id
  end

  sig { returns(T.nilable(String)) }
  def actor_preferred_avatar_url
    T.let(user&.primary_avatar_url(20), T.nilable(String))
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String),
      current_user: User
    )
    .returns(T::Array[UserBypassActor])
  end
  def self.suggest_bypassers(source, query, current_user)
    return [] if query.nil? || query.strip.empty?
    return [] unless source.is_a?(Repository)
    repository = source
    organization = repository.organization

    # Note: Leaving this as an option if we want to scope it down further than what branch_protections does.
    #         For example, if we only want to return org members or only members of the business associated with the org.
    # If organization is supplied, this query will return only members of that organization
    #                    (returns only public members if actor not a member of the org, all org members otherwise)
    # include_business_orgs - If org_members_only is supplied this will return only members
    #                         of the supplied organization's business.

    business = repository.business
    org_members_only = !!organization
    include_business_orgs = !!organization&.business&.present?
    include_outside_collaborators = !!organization

    autocomplete_query = AutocompleteQuery.new(
      current_user,
      query,
      organization:,
      repository:,
      business:,
      org_members_only:,
      include_business_orgs:,
      include_outside_collaborators:,
    )
    bypass_actors = autocomplete_query.suggestions.grep(User).map do |user|
      UserBypassActor.new({ actor: user })
    end
    return [] if bypass_actors.empty?
    filter_write_actors(bypass_actors, source)
  end

  sig do
    params(
      bypassers: T::Array[UserBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: Targeting::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    repo = targetable.get_attribute(Targeting::Attribute::Repository)
    return [] unless repo.is_a?(Repository)

    user = actor.is_a?(User) ? actor : actor.try(:owner)
    return [] if user.nil?
    return [] unless repo.writable_by?(user)

    allowed_modes = []
    bypassers.group_by { |bypass| bypass.bypass_mode }.each do |mode, user_bypassers|
      bypasser_user_ids = user_bypassers.map { |bypasser| bypasser.actor_id }
      allowed_modes << mode if bypasser_user_ids.include?(user.id)
    end
    allowed_modes
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.bypassable_user_ids(repository, bypass_actors)
    bypass_actors.map(&:actor_id).compact
  end

  sig { params(actors: T::Array[UserBypassActor], source: RuleEngine::Types::RuleSource).returns(T::Array[UserBypassActor]) }
  def self.filter_write_actors(actors, source)
    actor_ids = actors.map(&:actor_id).compact
    write_users = user_ids_with_write_access(source, actor_ids_filter: actor_ids)
    actors.select do |actor|
      (write_users.include?(actor.actor_id)) ||
      # User owned repositories won't include the owner in the list of users, so explicitly check for that
      (source.is_a?(Repository) && !source.owner&.organization? && (actor.actor_id == source.owner_id))
    end
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      actor_ids_filter: T.nilable(T::Array[Integer])
    ).returns(T::Array[Integer])
  end
  def self.user_ids_with_write_access(source, actor_ids_filter: nil)
    source.actor_ids(type: User, min_action: :write, actor_ids_filter: actor_ids_filter)
  end

  sig { void }
  def check_for_repository_ruleset
    unless repository_ruleset&.source.is_a?(Repository)
      errors.add(:base, "User bypass actors can only be added to repository rulesets")
    end
  end
end
