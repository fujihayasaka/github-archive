# typed: true
# frozen_string_literal: true

class RepositoryMigrationBypassActor < RepositoryRulesetBypassActor
  validate :ensure_actor
  validate :ensure_bypass_mode

  sig { returns(String) }
  def self.display_type
    "RepositoryMigration"
  end

  sig { returns(String) }
  def self.display_name
    "Repository migrations"
  end

  def ensure_actor
    # the database column `actor_type` must be nil since this is not a valid AR association
    self.actor_type = nil
    self.actor_id = nil
  end

  def ensure_bypass_mode
    if self.bypass_mode == BYPASS_MODES[:pull_request]
      # This is a scoped deploy key, so it should not allow pull request bypass mode
      self.errors.add(:base, "repository migration bypass mode must not be 'PULL_REQUEST'")
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
    T.cast(bypassers_by_type, T::Array[RepositoryMigrationBypassActor])
    if bypassers_by_type.size > 1
      ruleset.errors.add(:base, "there can be only one repository migration bypass actor")
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
    .returns(T::Array[RepositoryMigrationBypassActor])
  end
  def self.suggest_bypassers(source, query)
    return [] unless (
      (source.is_a?(Business) && source.feature_enabled_for_source?(:octoshift_ops__enterprise_rulesets_repository_migrations)) ||
      (source.is_a?(Organization) && source.feature_enabled_for_source?(:octoshift_ops_org_rulesets_repository_migrations))
    )

    if query.nil? || display_name.downcase.include?(query)
      return [RepositoryMigrationBypassActor.new]
    end
    []
  end

  sig do
    params(
      bypassers: T::Array[RepositoryMigrationBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    business = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Enterprise)
    organization = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Organization)
    repository = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository)

    return [] unless (
      business&.feature_enabled_for_source?(:octoshift_ops__enterprise_rulesets_repository_migrations) ||
      organization&.feature_enabled_for_source?(:octoshift_ops_org_rulesets_repository_migrations)
    ) &&
      actor.is_a?(PublicKey) &&
      actor.respond_to?(:read_only?) && !actor.read_only? &&
      repository == actor.repository &&
      actor.respond_to?(:bypasses_policy?) && actor.bypasses_policy?

    # This is a scoped deploy key, so it should not allow pull request bypass mode
    bypassers.map(&:bypass_mode).select { |mode| mode != RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request] }
  end

end
