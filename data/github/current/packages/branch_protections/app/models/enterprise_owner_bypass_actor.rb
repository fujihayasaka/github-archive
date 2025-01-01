# typed: true
# frozen_string_literal: true

class EnterpriseOwnerBypassActor < RepositoryRulesetBypassActor
  before_validation :ensure_actor
  validate :ensure_in_enterprise

  def self.display_type
    "EnterpriseOwner"
  end

  def self.display_name
    "Enterprise owners"
  end

  def ensure_actor
    # the database column `actor_type` and `actor_id` must be nil since this is not a valid AR association
    self.actor_type = nil
    self.actor_id = nil
  end

  def ensure_in_enterprise
    return if repository_ruleset&.business

    self.errors.add("actor", "EnterpriseOwner role requires an enterprise")
  end

  sig do
    params(
      ruleset: RepositoryRuleset,
      bypassers_by_type: T::Array[RepositoryRulesetBypassActor]
    ).void
  end
  def self.validate_bypass_actors(ruleset, bypassers_by_type)
    T.cast(bypassers_by_type, T::Array[EnterpriseOwnerBypassActor])
    if bypassers_by_type.size > 1
      ruleset.errors.add(:base, "there can be only one enterprise owner bypass actor")
    end
  end

  sig { returns(String) }
  def actor_type
    self.class.display_type
  end

  sig { returns(String) }
  def actor_name
    self.class.display_name
  end

  sig { returns(String) }
  def actor_display_type
    self.class.display_type
  end

  def is_match?(bypasser)
    bypasser.type == self.type
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String)
    )
    .returns(T::Array[EnterpriseOwnerBypassActor])
  end
  def self.suggest_bypassers(source, query)
    enterprise = source.is_a?(Business) ? source : source.business
    return [] unless enterprise

    if query.nil? || display_name.downcase.include?(query)
      return [EnterpriseOwnerBypassActor.new({ actor_id: enterprise.id })]
    end
    []
  end

  sig do
    params(
      bypassers: T::Array[EnterpriseOwnerBypassActor],
      actor: RuleEngine::Types::Actor,
      repository: Repository
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, repository)
    allowed_modes = []
    user = actor.is_a?(User) ? actor : actor.owner

    bypassers.group_by { |bypass| bypass.bypass_mode }.each do |mode, _bypasser|
      if repository.business&.owner?(user)
        allowed_modes << mode
      end
    end
    allowed_modes
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.bypassable_user_ids(repository, bypass_actors)
    user_ids = []
    if repository.business.present?
      user_ids.push(*T.must(repository.business).owners.pluck(:id))
    end
    user_ids
  end
end
