# typed: true
# frozen_string_literal: true

class EnterpriseRoleBypassActor < RepositoryRulesetBypassActor
  validate :ensure_actor
  validate :ensure_valid_role

  ADMIN_NAME = "Enterprise admin"

  def self.display_type
    "EnterpriseRole"
  end

  sig { returns(T.nilable(EnterpriseRole)) }
  def role
    T.let(actor, T.nilable(EnterpriseRole))
  end

  sig { returns(T.nilable(String)) }
  def actor_name
    self.role&.name == "admin" ? ADMIN_NAME : role&.display_name
  end

  sig { returns(String) }
  def actor_type
    self.class.display_type
  end

  sig { returns(String) }
  def actor_display_type
    self.class.display_type
  end

  def ensure_actor
    errors.add(:base, "actor_id is required for EnterpriseRole") if actor_id.nil?
    errors.add(:actor, "must be an EnterpriseRole") unless actor_type == "EnterpriseRole"
  end

  def ensure_valid_role
    return if @validated_associations
    return if actor.nil?
    unless actor.is_a?(EnterpriseRole)
      errors.add("actor", "must be an EnterpriseRole")
      return
    end

    if actor.owner_id.present?
      # custom role
      enterprise = ruleset_enterprise
      if enterprise.present?
        unless EnterpriseRole.custom_roles_for_enterprise(enterprise).exists?(actor_id)
          errors.add("actor", "role must be part of the ruleset enterprise")
        end
      else
        errors.add("actor", "role must be part of the ruleset enterprise")
      end
    else
      errors.add("actor", "role must have an owner")
    end
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String),
      limit: Integer
    )
    .returns(T::Array[EnterpriseRoleBypassActor])
  end
  def self.suggest_bypassers(source, query, limit: 10)
    return [] unless source.is_a?(Business) &&
                     source.custom_enterprise_roles_supported? &&
                     source.erp_feature_enabled?(:custom_enterprise_role_feature) &&
                     source.enterprise_rulesets_enterprise_roles_enabled?

    bypass_actors = []


    EnterpriseRole.visible_roles(source).each do |role_to_add|
      if query.present?
        if role_to_add.name.downcase.start_with?(query)
          bypass_actors.unshift(EnterpriseRoleBypassActor.new(actor: role_to_add))
        elsif role_to_add.name.downcase.include?(query)
          bypass_actors.push(EnterpriseRoleBypassActor.new(actor: role_to_add))
        end
      else
        bypass_actors.push(EnterpriseRoleBypassActor.new(actor: role_to_add))
      end

      limit -= 1
      break if limit <= 0
    end

    bypass_actors
  end

  sig do
    params(
      bypassers: T::Array[EnterpriseRoleBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    repository = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository)
    return [] unless repository.is_a?(Repository) &&
                     repository.enterprise_rulesets_enterprise_roles_enabled?

    enterprise = repository.business
    return [] unless enterprise.present?

    allowed_modes = []

    enterprise_role_bypasses = bypassers.select { |bypass| bypass.actor.present? }
    return [] if enterprise_role_bypasses.empty?

    role_ids = enterprise_role_bypasses.map(&:actor_id)

    matches = EnterpriseRole.matching_roles?(enterprise, role_ids, actor)

    matches.each do |match|
      enterprise_role_bypasses.find { |bypass| bypass.actor_id == match.role_id }.tap do |bypass|
        allowed_modes << bypass.bypass_mode if bypass
      end
    end

    allowed_modes.uniq
  end

end
