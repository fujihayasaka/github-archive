# typed: true
# frozen_string_literal: true

class DeployKeyBypassActor < RepositoryRulesetBypassActor
  validate :ensure_actor
  validate :ensure_bypass_mode

  sig { returns(String) }
  def self.display_type
    "DeployKey"
  end

  sig { returns(String) }
  def self.display_name
    "Deploy keys"
  end

  def ensure_actor
    # the database column `actor_type` must be nil since this is not a valid AR association
    self.actor_type = nil
    self.actor_id = nil
  end

  def ensure_bypass_mode
    if self.bypass_mode == BYPASS_MODES[:pull_request]
      self.errors.add(:base, "deploy key bypass mode must not be 'PULL_REQUEST'")
    end
  end

  sig { returns(String) }
  def actor_name
    self.class.display_name
  end

  def actor_type
    # the database column `actor_type` must be nil since this is not a valid AR association
    # but we can fake it here
    self.class.display_type
  end

  sig do
    params(
      ruleset: RepositoryRuleset,
      bypassers_by_type: T::Array[RepositoryRulesetBypassActor]
    ).void
  end
  def self.validate_bypass_actors(ruleset, bypassers_by_type)
    T.cast(bypassers_by_type, T::Array[DeployKeyBypassActor])
    if bypassers_by_type.size > 1
      ruleset.errors.add(:base, "there can be only one deploy key bypass actor")
    end
  end

  def is_match?(bypasser)
    bypasser.type == self.type
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String)
    )
    .returns(T::Array[DeployKeyBypassActor])
  end
  def self.suggest_bypassers(source, query)
    if query.nil? || display_name.downcase.include?(query)
      return [DeployKeyBypassActor.new]
    end
    []
  end

  sig do
    params(
      bypassers: T::Array[DeployKeyBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    return [] unless actor.is_a?(PublicKey)
    return [] if !actor.respond_to?(:read_only?) || actor.read_only?
    return [] if targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository) != actor.repository

    # deploy keys do not support the PULL_REQUEST mode
    bypassers.map(&:bypass_mode).select { |mode| mode != RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request] }
  end
end
