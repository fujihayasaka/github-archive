# typed: true
# frozen_string_literal: true

class OrganizationAdminBypassActor < RepositoryRulesetBypassActor
  validate :ensure_in_organization
  before_validation :ensure_actor

  def self.display_type
    "OrganizationAdmin"
  end

  def self.display_name
    "Organization admin"
  end

  sig { returns(String) }
  def actor_name
    self.class.display_name
  end

  def actor_type
    # the database column `actor_type` must be nil since this is not a valid AR association
    # but we can fake it here for serialization
    self.class.display_type
  end

  def is_match?(bypasser)
    bypasser.type == self.type
  end

  def ensure_in_organization
    return if @validated_associations
    source = repository_ruleset&.source
    return unless source

    return if source.is_a?(Business) ||
              source.is_a?(Organization) ||
              (source.is_a?(Repository) && source.owner&.organization?)

    self.errors.add(:base, "ruleset source must be in an organization")
  end

  def ensure_actor
    # the database column `actor_type` must be nil since this is not a valid AR association
    self.actor_type = nil
    self.actor_id = nil
  end

  sig do
    params(
      ruleset: RepositoryRuleset,
      bypassers_by_type: T::Array[RepositoryRulesetBypassActor]
    ).void
  end
  def self.validate_bypass_actors(ruleset, bypassers_by_type)
    T.cast(bypassers_by_type, T::Array[OrganizationAdminBypassActor])
    if bypassers_by_type.size > 1
      ruleset.errors.add(:base, "there can be only one organization admin bypass actor")
    end
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String)
    )
    .returns(T::Array[OrganizationAdminBypassActor])
  end
  def self.suggest_bypassers(source, query)
    if source.is_a?(Repository) && !source.owner.is_a?(Organization)
      # don't include org admins if this is a repo without an org
      return []
    end

    if query.nil? || display_name.downcase.include?(query)
      return [OrganizationAdminBypassActor.new]
    end
    []
  end

  sig do
    params(
      bypassers: T::Array[OrganizationAdminBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    return [] unless (org = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Organization)).is_a?(Organization)
    allowed_modes = []

    org_admin =
    if actor.is_a?(Bot)
      org.resources.organization_administration.writable_by?(actor)
    elsif actor.is_a?(User)
      org.adminable_by?(actor)
    elsif actor.is_a?(PublicKey)
      actor.created_by_user? && !org.rules_disallow_deploy_key_org_bypass?
    else
      false
    end

    if org_admin
      bypassers.group_by { |bypass| bypass.bypass_mode }.each do |mode, _bypasser|
        allowed_modes << mode
      end
    end
    allowed_modes
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.bypassable_user_ids(repository, bypass_actors)
    ids = []
    org = repository.owner
    if org.is_a?(Organization)
      ids = T.cast(org, Organization).admin_ids
    end
    ids
  end
end
