# typed: true
# frozen_string_literal: true

class RepositoryRulesetBypassActor < ApplicationRecord::Repositories
  self.table_name = "repository_ruleset_bypass_actors"

  include GitHub::Memoizer

  VALID_ACTORS = %w(Team Integration RepositoryRole EnterpriseTeam EnterpriseOwner)
  ALLOWED_BASE_ROLES = %w(write maintain admin)
  ACTOR_LIMIT = 75

  belongs_to :repository_ruleset, class_name: "RepositoryRuleset"

  belongs_to :actor, polymorphic: true

  validates :repository_ruleset, presence: true

  validates :actor, presence: true
  validates :actor_type, inclusion: { in: VALID_ACTORS }

  before_validation :ensure_actor_type
  before_validation :ensure_actor_id
  before_validation :ensure_repository_role

  def ensure_actor_type
    if self.actor_type == "Business"
      self.actor_type = "EnterpriseOwner"
    end
  end

  def ensure_actor_id
    if self.actor_type == "EnterpriseOwner"
      self.actor_id = self.repository_ruleset&.business&.id || 0
    end
  end

  def ensure_repository_role
    if actor.is_a?(RepositoryRole) && actor_type == "Role"
      self.actor_type = "RepositoryRole"
    end
  end

  validate :ensure_valid_enterprise_owners
  validate :ensure_valid_enterprise_team
  validate :ensure_valid_team
  validate :ensure_valid_role
  validate :ensure_valid_integration
  validate :ensure_actor_limit_not_exceeded, on: :create

  sig { params(bypass_actors: T::Array[RepositoryRulesetBypassActor], ruleset: RepositoryRuleset).void }
  def self.validate_all_associations(bypass_actors, ruleset)
    bypass_actors.each { _1.instance_variable_set(:@validated_associations, true) }

    validate_enterprise_owners(bypass_actors, ruleset.business)
    validate_enterprise_teams(bypass_actors, ruleset.source)
    validate_teams(bypass_actors, ruleset.organization)
    validate_roles(bypass_actors, ruleset.organization)
    validate_integrations(bypass_actors, ruleset)
    validate_actor_count(bypass_actors, ruleset)
  end

  def self.validate_actor_count(bypass_actors, ruleset)
    available_count = ACTOR_LIMIT - ruleset.bypass_actors.count
    new_actors_over_limit = bypass_actors.select(&:new_record?)[available_count..-1]
    new_actors_over_limit&.each do |bypass_actor|
      bypass_actor.errors.add(:base, RepositoryRuleset::BypassActorsLimitError::MESSAGE)
    end
  end

  sig do
    params(
      bypass_actors: T::Array[RepositoryRulesetBypassActor],
      business: T.nilable(Business),
    ).void
  end
  def self.validate_enterprise_owners(bypass_actors, business)
    bypassers = bypass_actors.filter { |bypass_actor| bypass_actor.actor_type == "EnterpriseOwner" }
    return if bypassers.empty?

    if !business.present?
      bypassers.each do |bypass|
        bypass.errors.add("actor", "EnterpriseOwner role requires an enterprise")
      end
    end
  end

  def self.validate_enterprise_teams(bypass_actors, enterprise)
    team_actors = bypass_actors.filter { |bypass_actor| bypass_actor.actor_type == "EnterpriseTeam" }
    return if team_actors.empty?

    unless enterprise&.is_a?(Business)
      team_actors.each do |bypass_actor|
        bypass_actor.errors.add("actor", "enterprise teams are only supported on enterprise rulesets")
      end
      return
    end

    team_ids = team_actors.map(&:actor_id)

    teams = if team_ids.any?
      enterprise.enterprise_teams.where(id: team_ids).index_by(&:id)
    else
      {}
    end

    team_actors.each do |bypass_actor|
      bypass_actor.errors.add("actor", "enterprise team not found") unless teams.key?(bypass_actor.actor_id)
    end
  end

  sig { params(bypass_actors: T::Array[RepositoryRulesetBypassActor], organization: T.nilable(Organization)).void }
  def self.validate_teams(bypass_actors, organization)
    team_actors = bypass_actors.filter { |bypass_actor| bypass_actor.actor_type == "Team" }
    team_ids = team_actors.map(&:actor_id)

    teams = if organization.present? && team_ids.any?
      organization.teams.where(id: team_ids, privacy: :closed).index_by(&:id)
    else
      {}
    end

    team_actors.each do |bypass_actor|
      bypass_actor.errors.add("actor", "team must be part of the ruleset source or owner organization") unless teams.key?(bypass_actor.actor_id)
    end
  end

  sig { params(bypass_actors: T::Array[RepositoryRulesetBypassActor], ruleset: RepositoryRuleset).void }
  def self.validate_integrations(bypass_actors, ruleset)
    integration_actors = bypass_actors.filter { |bypass_actor| bypass_actor.actor_type == "Integration" }
    integration_ids = integration_actors.map(&:actor_id)

    integrations = if integration_ids.any?
      RulesEngine::Suggestions.integrations_for(ruleset.source).index_by { |integration| integration[:id] }
    else
      {}
    end

    integration_actors.each do |bypass_actor|
      bypass_actor.errors.add("actor", "integration must be part of the ruleset source or owner organization") unless integrations.key?(bypass_actor.actor_id)
    end
  end

  sig do
    params(
      bypass_actors: T::Array[RepositoryRulesetBypassActor],
      organization: T.nilable(Organization),
    ).void
  end
  def self.validate_roles(bypass_actors, organization)
    default_role_ids = T.let([], T::Array[Integer])
    custom_role_ids = T.let([], T::Array[Integer])

    role_actors = bypass_actors.filter { |bypass_actor| bypass_actor.actor_type == "RepositoryRole" }
    role_actors.each do |role_actor|
      if role_actor.actor.nil?
        role_actor.errors.add("actor", "repository role #{role_actor.actor_id} is invalid")
        next
      end
      if role_actor.actor.owner_id.present?
        custom_role_ids.push(role_actor.actor_id)
      else
        default_role_ids.push(role_actor.actor_id)
      end
    end

    default_roles = RepositoryRole.where(owner_id: nil, id: default_role_ids).index_by(&:id)
    custom_roles = if organization.present?
      RepositoryRole.custom_roles_for_org(organization).where(id: custom_role_ids).index_by(&:id)
    else
      {}
    end

    role_actors.each do |bypass_actor|
      default_role = default_roles[bypass_actor.actor_id]

      if default_role.present?
        next if ALLOWED_BASE_ROLES.include?(default_role.name)

        bypass_actor.errors.add("actor", "base role does not have write permissions")
        next
      end

      bypass_actor.errors.add("actor", "role must be part of the ruleset source or owner organization") unless custom_roles.key?(bypass_actor.actor_id)
    end
  end

  sig { returns(String) }
  def actor_name
    if actor_type == "DeployKey"
      "Deploy keys"
    elsif actor_type == "EnterpriseOwner"
      "Enterprise owners"
    else
      actor.name
    end
  end

  sig { returns(T.nilable(String)) }
  def actor_owner_name
    return nil unless actor.is_a?(Integration)
    actor.owner.display_login
  end

  def ensure_valid_enterprise_team
    return true unless actor_type == "EnterpriseTeam"

    self.class.validate_enterprise_teams([self], T.must(repository_ruleset).source) unless @validated_associations
    self.errors[:actor].empty?
  end

  def ensure_valid_enterprise_owners
    return true unless actor_type == "EnterpriseOwner"
    self.class.validate_enterprise_owners([self], T.must(repository_ruleset).business) unless @validated_associations
    self.errors[:actor].empty?
  end

  def ensure_valid_team
    return true unless actor_type == "Team"

    self.class.validate_teams([self], ruleset_organization) unless @validated_associations

    self.errors[:actor].empty?
  end

  def ensure_valid_role
    return true unless actor_type == "RepositoryRole"

    self.class.validate_roles([self], ruleset_organization) unless @validated_associations

    self.errors[:actor].empty?
  end

  def ensure_valid_integration
    return true unless actor_type == "Integration"

    self.class.validate_integrations([self], T.must(repository_ruleset)) unless @validated_associations

    self.errors[:actor].empty?
  end

  def ensure_actor_limit_not_exceeded
    if !@validated_associations && repository_ruleset&.bypass_actors&.count.to_i >= ACTOR_LIMIT
      errors.add(:base, RepositoryRuleset::BypassActorsLimitError::MESSAGE)
    end
  end

  AUDITABLE_FIELDS = %i[bypass_mode].freeze

  # if this enum is updated, please update current_user_can_bypass in
  # repositories_dependency.rb and its API response type in repository-ruleset.yaml
  BYPASS_MODES = {
    any: 0,
    pull_request: 1,
  }.with_indifferent_access.freeze
  # This can be uncommnted once we remove the feature flag
  # enum :bypass_mode, BYPASS_MODES, default: :any

  # initialize an org admin bypass actor
  # org admin bypass actors are not valid bypass actors
  # but is stored as an enum on the rulesets bypass_mode column
  # this is a representation of what an org admin bypass actor would look like
  sig do
    params(
      bypass_mode: Symbol
    ).returns(RepositoryRulesetBypassActor)
  end
  def self.new_org_admin_bypass_actor(bypass_mode: :any)
    new.org_admin_bypass_actor(bypass_mode: bypass_mode)
  end

  sig do
    params(
      bypass_mode: Symbol
    ).returns(RepositoryRulesetBypassActor)
  end
  def org_admin_bypass_actor(bypass_mode: :any)
    self.actor_id = RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin]
    self.actor_type = "OrganizationAdmin"
    self.bypass_mode = BYPASS_MODES[bypass_mode]
    self
  end

  sig do
    params(
      bypass_mode: Symbol
    ).returns(RepositoryRulesetBypassActor)
  end
  def self.new_deploy_key_bypass_actor(bypass_mode: :any)
    new.deploy_key_bypass_actor(bypass_mode: bypass_mode)
  end

  sig do
    params(
      bypass_mode: Symbol
    ).returns(RepositoryRulesetBypassActor)
  end
  def deploy_key_bypass_actor(bypass_mode: :any)
    self.actor_id = DeployKey.id
    self.actor_type = DeployKey.type
    self.bypass_mode = BYPASS_MODES[bypass_mode]
    self
  end

  sig { returns(T.nilable(Organization)) }
  memoize def ruleset_organization
    return unless repository_ruleset.present?
    source = T.must(repository_ruleset).source
    return if source.is_a?(Business)

    org = T.let(nil, T.nilable(Organization))
    if source.is_a?(Organization)
      org = source
    elsif source.owner.is_a?(Organization)
      org = source.owner
    end
    org
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.matching_user_ids(repository, bypass_actors)
    user_ids = T.let([], T::Array[Integer])
    teams = T.let([], T::Array[Team])
    custom_roles = T.let([], T::Array[RepositoryRole])
    system_roles = T.let([], T::Array[RepositoryRole])

    GitHub::PrefillAssociations.prefill_associations(bypass_actors, [:actor])

    bypass_actors.each do |bypass_actor|
      case bypass_actor.actor_type
      when "Team"
        teams.push(bypass_actor.actor)
      when "RepositoryRole"
        if ALLOWED_BASE_ROLES.include?(bypass_actor.actor.name)
          system_roles.push(bypass_actor.actor)
          next
        end
        custom_roles.push(bypass_actor.actor)
      when "EnterpriseOwner"
        # the `actor` association cannot be used for enterprises because the ability infrastructure gets confused by the `EnterpriseOwner` wrapper class
        business = Business.find_by(id: bypass_actor.actor_id)
        if business.present?
          user_ids.push(*business.owners.pluck(:id))
        end
      end
    end

    user_ids.push(*Team.member_ids_of(teams.map(&:id), immediate_only: false)) if teams.any?

    if custom_roles.any?
      user_ids.push(*UserRole.where(actor_type: "User", target: repository, role_id: custom_roles).pluck(:actor_id))

      team_ids = UserRole.where(actor_type: "Team", target: repository, role_id: custom_roles).pluck(:actor_id) - teams.pluck(:id)
      user_ids.push(*Team.member_ids_of(team_ids, immediate_only: false)) if team_ids.any?
    end

    if system_roles.any?
      # Find minimum allowed action based on ranking
      min_action = T.must(system_roles.sort_by(&:action_rank).first).name

      ##
      # user_ids_with_privileged_access only accepts read, write, or admin. We fallback to write for other roles
      # supported in ruleset bypasses as these are commonly based on the write role.
      #
      min_action = "write" unless min_action == "write" || min_action == "admin"

      eligible_user_ids = repository.user_ids_with_privileged_access(min_action: min_action.to_sym) - user_ids
      eligible_users = User.batched_scope(:id, values: eligible_user_ids).to_a.index_by(&:id)

      _, user_to_highest_role_mapping = repository.batch_action_and_role_level_for(eligible_users.values)

      user_to_highest_role_mapping.each do |user_id, role|
        user = eligible_users[user_id]
        permissions = Repository.permissions_hash(role)

        system_roles.each do |system_role|
          next unless permissions[Team::ABILITIES_TO_PERMISSIONS[system_role.name].to_sym]

          user_ids.push(user_id)
          break
        end
      end
    end

    user_ids.uniq
  end

  def changes_payload
    {}.tap do |changes|
      AUDITABLE_FIELDS.each do |field|
        if saved_change_to_attribute?(field)
          if field == :bypass_mode
            attribute = attribute_before_last_save(field) == 0 ? "always" : "pull_request"
            changes["old_#{field}".to_sym] = attribute
          else
            changes["old_#{field}".to_sym] = attribute_before_last_save(field)
          end
        end
      end
    end
  end

  def event_payload
    {
      id: id,
      actor_id: actor_id,
      actor_type: actor_type,
      bypass_mode: bypass_mode == 1 ? "pull_request" : "always"
    }
  end

  class DeployKey
    def self.id
      nil
    end

    def self.type
      "DeployKey"
    end

    def self.name
      "Deploy keys"
    end
  end
end
