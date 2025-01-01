# typed: true
# frozen_string_literal: true

class RepositoryRulesetBypassActor < ApplicationRecord::Repositories
  self.table_name = "repository_ruleset_bypass_actors"

  include GitHub::Memoizer
  include Scientist

  VALID_ACTORS = %w(Team Integration RepositoryRole EnterpriseTeam EnterpriseOwner)
  ALLOWED_BASE_ROLES = %w(write maintain admin)
  ACTOR_LIMIT = 75

  belongs_to :repository_ruleset, class_name: "RepositoryRuleset"

  belongs_to :actor, polymorphic: true, optional: true

  validates :repository_ruleset, presence: true
  validate :ensure_type
  before_validation :ensure_repository_role
  before_validation :populate_type

  def populate_type
    if self.type.blank? && self.actor_type.present?
      self.type = self.class.type_from_actor_type(self.actor_type)
    end
  end

  def ensure_type
    errors.add(:type, "is missing") unless self.type.present?
  end

  sig { params(actor_type: T.nilable(String)).returns(T.nilable(String)) }
  def self.type_from_actor_type(actor_type)
    case actor_type
    when "Team"
      "TeamBypassActor"
    when "Integration"
      "IntegrationBypassActor"
    when "RepositoryRole"
      "RepositoryRoleBypassActor"
    when "EnterpriseTeam"
      "EnterpriseTeamBypassActor"
    when "EnterpriseOwner"
      "EnterpriseOwnerBypassActor"
    when "DeployKey"
      "DeployKeyBypassActor"
    when "OrganizationAdmin"
      "OrganizationAdminBypassActor"
    end
  end

  def ensure_repository_role
    if self.actor_type == "Role"
      self.actor_type = "RepositoryRole"
    end
  end

  validate :ensure_valid_enterprise_owners
  validate :ensure_valid_enterprise_team
  validate :ensure_valid_team
  validate :ensure_valid_role
  validate :ensure_valid_integration
  validate :ensure_actor_limit_not_exceeded, on: :create
  validate :legacy_actor_exists
  validate :ensure_bypass_mode

  sig do
    params(
      ruleset: RepositoryRuleset,
      bypassers_by_type: T::Array[RepositoryRulesetBypassActor]
    ).void
  end
  def self.validate_bypass_actors(ruleset, bypassers_by_type)
    # subclasses can override this method to validate the bypass actors relative to the ruleset
    # The bypassers_by_type set is a list of the specific subtype
  end

  def ensure_bypass_mode
    unless BYPASS_MODES.values.include?(bypass_mode)
      errors.add(:bypass_mode, "is invalid")
    end

    return unless repository_ruleset&.target

    if bypass_mode != 0 && repository_ruleset&.target != "branch"
      errors.add(:base, "bypass mode must be 'ALWAYS' for #{repository_ruleset&.target} rulesets")
    end
  end

  # TODO: Move this check to individual bypass actor classes and fix tests
  def legacy_actor_exists
    # Temporary until we fully migrate to the new STI classes
    # Validate the actor exists for the bypass actors that expect an actor
    return if self.actor_type == "DeployKey" || self.type == "DeployKeyBypassActor"
    return if self.actor_type == "OrganizationAdmin" || self.type == "OrganizationAdminBypassActor"
    return if self.actor_type == "EnterpriseOwner" || self.type == "EnterpriseOwnerBypassActor"

    unless VALID_ACTORS.include?(actor_type)
      errors.add(:actor_type, "is invalid")
    end

    if actor.nil?
      errors.add(:base, "Invalid bypass actor: '{{actor_id: #{actor_id}}, {actor_type: #{actor_type}}}'")
    end
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      current_user: User,
      query: T.nilable(String),
      exclude_integrations: T.nilable(T::Boolean)
    )
    .returns(T::Array[RepositoryRulesetBypassActor])
  end
  def self.suggest_all_bypassers(source, current_user, query, exclude_integrations: false)
    query = query&.downcase
    bypassers = []
    bypassers << OrganizationAdminBypassActor.suggest_bypassers(source, query)
    bypassers << DeployKeyBypassActor.suggest_bypassers(source, query)
    bypassers << RepositoryRoleBypassActor.suggest_bypassers(source, query)
    bypassers << TeamBypassActor.suggest_bypassers(source, current_user, query)
    bypassers << EnterpriseTeamBypassActor.suggest_bypassers(source, query)
    bypassers << EnterpriseOwnerBypassActor.suggest_bypassers(source, query)
    bypassers << IntegrationBypassActor.suggest_bypassers(source, query) unless exclude_integrations
    bypassers.flatten
  end

  class Serialized < T::Struct
    const :id, T.nilable(Integer)
    const :type, T.nilable(String)
    const :actorId, T.nilable(Integer)
    const :actorType, T.nilable(String)
    const :name, T.nilable(String)
    const :bypassMode, String
    const :preferred_avatar_url, T.nilable(String)
    const :owner, T.nilable(String)
    const :global_relay_id, T.nilable(String)
  end

  sig { returns(Serialized) }
  def to_hash
    Serialized.new(
      id:,
      type:,
      actorId: actor_id,
      actorType: actor_display_type,
      name: actor_name,
      bypassMode: bypass_mode == 1 ? "pull_request" : "always",
      preferred_avatar_url: actor_preferred_avatar_url, # swap to camelCase separately
      owner: actor_owner_name,
      global_relay_id: actor_global_relay_id, # swap to camelCase separately
    )
  end

  sig do
    params(
      all_bypassers: T::Array[RepositoryRulesetBypassActor],
      actor: RuleEngine::Types::Actor,
      repository: Repository  # TODO: Should this be the ruleset or the source or target of the ruleset?
    ).returns(T::Array[Symbol])
  end
  def self.all_allowed_bypass_modes(all_bypassers, actor, repository)
    modes = []

    # Because this method is called a lot, we need to minimize SQL queries.
    # So instead of iterating over each bypass actor individually, aggregate by type
    # and make a single call to each class
    groups = all_bypassers.group_by(&:type)
    groups.each do |type, bypassers_by_type|
      klass = type.constantize
      modes << klass.allowed_bypass_modes(bypassers_by_type, actor, repository)
    end
    modes = modes.flatten.compact.uniq.map { |mode| RepositoryRulesetBypassActor::BYPASS_MODES.key(mode).to_sym }
  end

  sig { params(bypass_mode: T.nilable(T.any(Integer, String))).returns(Integer) }
  private_class_method def self.db_actor_bypass_mode(bypass_mode)
    if bypass_mode.is_a?(Integer)
      if BYPASS_MODES.values.include?(bypass_mode)
        return bypass_mode
      else
        return BYPASS_MODES[:any]
      end
    end

    if bypass_mode == "always" || bypass_mode.nil?
      # default value
      BYPASS_MODES[:any]
    else
      BYPASS_MODES[bypass_mode.to_sym]
    end
  end

  sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(RepositoryRulesetBypassActor) }
  def self.from_hash(hash)
    hash = hash.symbolize_keys

    actor_type = hash[:actor_type]
    hash[:type] ||= self.type_from_actor_type(hash[:actor_type])
    raise RepositoryRuleset::Error.new("#{actor_type} is not a valid actor type") if hash[:type].nil?

    hash[:bypass_mode] = db_actor_bypass_mode(hash[:bypass_mode])

    # remove any keys not part of the bypass actor attributes so instantiation doesn't fail
    hash.slice!(:id, :type, :actor_type, :actor_id, :bypass_mode)
    bypasser = self.new(hash)
    bypasser
  end

  sig do
    params(
      ruleset: RepositoryRuleset,
      hashes: T::Array[T::Hash[T.untyped, T.untyped]]
    ).returns(T::Array[T::Hash[T.untyped, T.untyped]])
  end
  def self.translate_bypass_actors(ruleset, hashes)
    bypass_actors = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

    hashes.each do |hash|
      # instantiate a bypass actor and raise if it's not valid
      bypasser = self.from_hash(hash)
      bypasser.repository_ruleset = ruleset

      unless bypasser.valid?
        raise ValidationError.new(bypasser.errors.full_messages)
      end

      bypass_actors << hash
    end
    bypass_actors
  end

  sig do
    params(
      ruleset: RepositoryRuleset,
      bypass_actors_hash: T::Array[T::Hash[T.untyped, T.untyped]]
    ).returns(T::Boolean)
  end
  def self.upsert_bypass_actors(ruleset, bypass_actors_hash)
    @bypass_actors_added = []
    @bypass_actors_updated = []
    @bypass_actors_deleted = []
    bypass_actors_unchanged = []
    bypass_actors_processed = []

    existing_bypassers = ruleset.bypass_actors

    new_bypassers = []
    bypass_actors_hash.each do |hash|
      # instantiate a bypass actor and raise if it's not valid
      bypasser = self.from_hash(hash)

      # ignore any duplicates to what we've already processed
      next if bypass_actors_processed.find { |ba| ba.is_match?(bypasser) }
      bypass_actors_processed << bypasser

      # for each new bypass actor, try to find a matching existing bypass actor
      existing = existing_bypassers.find { |ba| ba.is_match?(bypasser) }

      if existing
        if existing.bypass_mode == bypasser.bypass_mode
          bypass_actors_unchanged << existing
        else
          # update the existing bypass actor attributes
          existing.bypass_mode = bypasser.bypass_mode
          @bypass_actors_updated << existing
        end
      else
        bypasser.repository_ruleset = ruleset
        @bypass_actors_added << bypasser
      end
    end

    # Delete existing bypass actors that were not in the new list.
    # Do this before adding the new actors so we stay under the bypass_actor limit
    @bypass_actors_deleted = existing_bypassers - bypass_actors_unchanged - @bypass_actors_updated
    @bypass_actors_deleted.each do |bypasser|
      ruleset.bypass_actors.destroy(bypasser)
    end

    changed_bypassers = @bypass_actors_added + @bypass_actors_updated
    RepositoryRulesetBypassActor.validate_all_associations(changed_bypassers, ruleset)

    ruleset.bypass_actors << @bypass_actors_added

    # add the new bypass actors to the ruleset and validate it
    changed_bypassers.each do |bypasser|
      raise ValidationError.new(bypasser.errors) unless bypasser.valid?

      # If the ruleset is new, delay saving the bypass actor until the ruleset is saved
      # This is because the bypass actor table requires a ruleset_id and this may be nil if the ruleset fails validation
      bypasser.save! if ruleset.persisted?
    end

    ruleset.bypass_actors_added = @bypass_actors_added
    ruleset.bypass_actors_updated = @bypass_actors_updated
    ruleset.bypass_actors_deleted = @bypass_actors_deleted

    @bypass_actors_added.any? || @bypass_actors_updated.any? || @bypass_actors_deleted.any?
  end

  # returns true if the bypasser is a match for the given bypass actor
  # some subclasses may not have an actor_id and override this method
  def is_match?(bypasser)
    bypasser.actor_type == self.actor_type && bypasser.actor_id == self.actor_id
  end

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
        bypass_actor.errors.add(:base, "actor_id is required for EnterpriseTeam") if bypass_actor.actor_id.nil?
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
      bypass_actor.errors.add(:base, "actor_id is required for Team") if bypass_actor.actor_id.nil?
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
      bypass_actor.errors.add(:base, "actor_id is required for Integration") if bypass_actor.actor_id.nil?
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
      role_actor.errors.add(:base, "actor_id is required for RepositoryRole") if role_actor.actor_id.nil?

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

  # if the actor no longer exists, this method will return nil
  sig { returns(T.nilable(String)) }
  def actor_name
    actor&.try(:name)
  end

  sig { returns(T.nilable(String)) }
  def actor_owner_name
    nil
  end

  sig { returns(T.nilable(String)) }
  def actor_preferred_avatar_url
    nil
  end

  sig { returns(String) }
  def actor_display_type
    actor_type
  end

  sig { returns(T.nilable(String)) }
  def actor_global_relay_id
    nil
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
  def self.bypassable_user_ids(repository, bypass_actors)
    # if subclasses support users they need to override this
    []
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.matching_user_ids(repository, bypass_actors)
    GitHub::PrefillAssociations.prefill_associations(bypass_actors, [:actor])
    ids = []
    groups = bypass_actors.group_by(&:type)
    groups.each do |type, bypassers_by_type|
      klass = type.constantize
      ids << klass.bypassable_user_ids(repository, bypassers_by_type)
    end
    ids.flatten.compact.uniq
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

  def to_suggestions_hash
    {
      actorId: actor_id,
      actorType: actor_display_type.to_sym,
      name: actor_name,
      preferred_avatar_url: actor_preferred_avatar_url,
      owner: actor_owner_name,
    }
  end

  def event_payload
    # TODO: Can we consolidate this with the to_hash method defined in subclasses?
    {
      id: id,
      actor_id: actor_id,
      actor_type: actor_type,
      bypass_mode: bypass_mode == 1 ? "pull_request" : "always"
    }
  end

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
    end

    def to_a
      self.errors.to_a
    end
  end
end
