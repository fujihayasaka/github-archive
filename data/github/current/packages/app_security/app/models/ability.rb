# typed: false
# frozen_string_literal: true

# Public: A row in our permission system. An Ability represents the
# combination of a actor, a subject, and an action. An Ability may also have
# an ancestor, an Ability that's ultimately responsible for its existence.
#
#   https://thehub.github.com/engineering/products-and-services/authorization/abilities/
#
# We're moving over to using Ability very carefully, so please consider
# talking with someone from @github/abilities before you dive in.
class Ability < ApplicationRecord::Domain::IamAbilities
  include Comparable
  include Instrumentation::Model
  include Ability::OrganizationDependency
  include Ability::ProjectDependency
  include Ability::RepositoryDependency
  include GitHub::BatchedScope

  BATCH_SIZE = 100 # how many records to insert or delete at a time

  FGP_ACTORS = %w[
    IntegrationInstallation
    OauthAuthorization
  ].freeze

  # This defines the how privileged an action is in relation to
  # other actions. This includes roles, which aren't ability actions,
  # but need to be compared against the privilege an ability action grants.
  ACTION_RANKING = {
    read: 0,
    triage: 0.5,
    write: 1,
    maintain: 1.5,
    admin: 2,
  }

  # This defines the next-most privileged action for a role.
  NEXT_HIGHEST_ABILITY_FOR_ROLE = {
    triage: :write,
    maintain: :admin
  }.with_indifferent_access.freeze

  # This defines how an all repo role ability maps to an ability action
  ALL_REPO_ROLE_FGP_ABILITY = {
    "read_repo" => :read,
    "write_repo" => :write,
    "admin_repo" => :admin,
  }

  enum :action, { read: 0, write: 1, admin: 2 }
  enum :priority, { indirect: 0, direct: 1 }

  attr_accessor :grantor_id, :role_name

  # Public: The valid actions that an Ability can have.
  #
  # Returns an array of symbols.
  def self.valid_actions
    self.actions.keys.map(&:to_sym)
  end

  # Public: Is the specified action valid?
  #
  # action - The action to test validity of. Can be a string or a symbol.
  #
  # Returns a boolean.
  def self.valid_action?(action)
    self.actions.include?(action)
  end

  validates :actor_id, presence: true
  validates :actor_type, presence: true
  validates :action, presence: true
  validates :subject_id, presence: true
  validates :subject_type, presence: true

  # NOTE: these associations only work if the related participant is an
  # ActiveRecord model.
  belongs_to :actor,   polymorphic: true
  belongs_to :subject, polymorphic: true

  # The direct ability closest to a subject in an indirect ability
  belongs_to :parent, class_name: "Ability", foreign_key: "parent_id" # rubocop:todo Rails/InverseOf

  scope :newest_first, -> { order(id: :desc) }

  # Returns a Relation to limit Ability records to those that grant
  # direct `:write` or `:admin` access.
  scope :direct_write, -> {
    direct.where(action: Ability.actions.values_at(:write, :admin))
  }

  # Returns a Relation to limit Ability records to those that grant
  # indirect `:read`, `:write` or `:admin` access via children abilities.
  scope :indirect_via_children, -> {
    joins(<<~SQL).
      LEFT OUTER JOIN `abilities` `children` ON
        `children`.`actor_type` = `abilities`.`subject_type` AND
        `children`.`actor_id` = `abilities`.`subject_id`
        /* abilities-join-audited */
    SQL
      where(priority: Ability.priorities.values_at(:direct, :indirect)).
      where(children: { priority: Ability.priorities[:direct] })
  }

  # Returns a Relation to limit Ability records to those that grant
  # indirect `:write` or `:admin` access via children abilities.
  scope :indirect_write_via_children, -> {
    indirect_via_children.where(children: { action: Ability.actions.values_at(:write, :admin) })
  }

  def self.grants(subject)
    directs = direct.where(
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
    )

    indirects = indirect_via_children.where(
      children: {
        subject_id: subject.ability_id,
        subject_type: subject.ability_type,
      },
    )

    directs + indirects
  end

  # The direct ability one step away from the subject in an indirect ability cascade
  def grandparent
    if grandparent_id && grandparent_id > 0
      @grandparent ||= Ability.find(grandparent_id)
    end
  end

  alias_method :original_subject, :subject

  def subject
    return self.original_subject unless FGP_ACTORS.include?(actor_type)

    ability_prefix = subject_type.split("/")[0..-2].join("/")
    resource       = subject_type.split("/").last

    case ability_prefix
    when Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX
      Repositories::Public.find_active!(subject_id).resources.public_send(resource)
    when Repository::Resources::ALL_ABILITY_TYPE_PREFIX
      # This will work for both users and orgs because of STI
      User.find(subject_id).repository_resources.public_send(resource)
    when Organization::Resources::ABILITY_TYPE_PREFIX, User::Resources::ABILITY_TYPE_PREFIX
      # This will work for both users and orgs because of STI
      User.find(subject_id).resources.public_send(resource)
    when ProtectedBranch::Resources::ABILITY_TYPE_PREFIX
      ProtectedBranch.find(subject_id).resources.public_send(resource)
    end
  end

  # Fake column representing a pointer to a grandparent
  def grandparent_id=(value)
    @grandparent_id = value
  end

  # Fake column representing a pointer to a grandparent.
  def grandparent_id
    # Use read_attribute because GitHub::SQL#models assigns attributes directly
    # instead of using attr_writers.
    @grandparent_id || read_attribute(:grandparent_id)
  end

  after_commit :instrument_grant, on: :create

  # Revoke role on ability destroy
  before_destroy :revoke_remaining_role!

  # NOTE: Moving instrument_revoke to commit callback causes test failures in
  # membership_hooks_test.rb and pull_request_serializer_test.rb, related to
  # the User being inaccessible once this callback is invoked.
  after_destroy :instrument_revoke # rubocop:disable GitHub/AfterCommitCallbackInstrumentation

  # Delete dependent abilities when an ability is destroyed.
  before_destroy do |ability|
    ability.delete_dependent_abilities
  end

  # Public: Can it be done?
  #
  # actor   - An Ability::Actor
  # action  - A :read, :write, or :admin Symbol
  # subject - An Ability::Subject
  #
  # Returns true or false.
  def self.can?(actor, action, subject)
    actor = actor.ability_delegate
    subject = subject.ability_delegate

    return false if actor.nil? || subject.nil?
    return false if actor.ability_id.nil? || subject.ability_id.nil?
    # A simpler `actor == subject` triggers `method_missing` when using `CollectionProxy` instances as actors or subjects,
    # causing the entire association to be queried and loaded
    return true  if actor.ability_type == subject.ability_type && actor.ability_id == subject.ability_id

    # start timer here since the above would skew the results
    timer = Timer.start

    key = ["can?",
      actor.ability_type, actor.ability_id,
      action,
      subject.ability_type, subject.ability_id]
    PermissionCache.fetch key do
      next true if higher_ability_allowed_in_cache?(actor, action, subject)
      next false if lower_ability_denied_in_cache?(actor, action, subject)
      ActiveRecord::Base.connected_to(role: :reading) do
        can_sql_query(actor, action, subject)
      end
    end
  ensure
    GitHub.dogstats.distribution("ability.can.dist.time", timer.elapsed_ms) unless timer.nil?
  end

  # Internal
  #
  # Return true if a more permissive action is in the cache and was allowed
  def self.higher_ability_allowed_in_cache?(actor, action, subject)
    case action
    when :read
      PermissionCache.get(ability_can_cache_key(actor, :write, subject)) ||
        PermissionCache.get(ability_can_cache_key(actor, :admin, subject))
    when :write
      PermissionCache.get(ability_can_cache_key(actor, :admin, subject))
    else
      false
    end
  end

  # Internal
  #
  # Return true if a less permissive action is in the cache and was denied
  def self.lower_ability_denied_in_cache?(actor, action, subject)
    case action
    when :admin
      PermissionCache.get(ability_can_cache_key(actor, :write, subject)) == false ||
        PermissionCache.get(ability_can_cache_key(actor, :read, subject)) == false
    when :write
      PermissionCache.get(ability_can_cache_key(actor, :read, subject)) == false
    else
      false
    end
  end

  def self.ability_can_cache_key(actor, action, subject)
    ["can?",
      actor.ability_type, actor.ability_id,
      action,
      subject.ability_type, subject.ability_id]
  end

  def self.can_sql_query(actor, action, subject)
    owning_org_id = subject.owning_organization_id

    sql_bindings = {
      actor_id: actor.ability_id,
      actor_type: actor.ability_type,
      action: Ability.actions[action],
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
      direct: Ability.priorities[:direct],
      admin_action: Ability.actions[:admin],
      owner_id: owning_org_id,
      owner_type: subject.owning_organization_type,
    }

    sql = Arel.sql <<-SQL, **sql_bindings
      SELECT 1
      /* abilities-join-audited */
      FROM   abilities
      WHERE  actor_id     = :actor_id
      AND    actor_type   = :actor_type
      AND    action      >= :action
      AND    subject_id   = :subject_id
      AND    subject_type = :subject_type
      AND    (priority    <= :direct)

      UNION

      SELECT 1
      FROM   abilities parent
      JOIN   abilities grandparent
      ON     grandparent.subject_type = parent.actor_type
      AND    grandparent.subject_id   = parent.actor_id
      AND    parent.priority          <= :direct
      AND    grandparent.priority     <= :direct
      WHERE  grandparent.actor_id     = :actor_id
      AND    grandparent.actor_type   = :actor_type
      AND    parent.action           >= :action
      AND    parent.subject_id        = :subject_id
      AND    parent.subject_type      = :subject_type
    SQL

    if owning_org_id
      sql += Arel.sql <<-SQL, **sql_bindings

        UNION

        SELECT 1
        FROM abilities
        WHERE actor_id   = :actor_id
        AND actor_type   = :actor_type
        AND subject_id   = :owner_id
        AND subject_type = :owner_type
        AND action       = :admin_action
      SQL
    end

    sql += Arel.sql "LIMIT 1"

    Ability.connection.select_value(sql).present?
  end

  def self.async_can?(actor, action, subject)
    Platform::Loaders::Ability.load(actor, subject).then do |max_action|
      if max_action
        max_action >= self.actions[action]
      else
        false
      end
    end
  end

  # Public: Queue a job to remove any abilities involving an actor and/or subject.
  #
  # participant - An Ability::Participant
  # async       - When true (default) will perform the clear! in a background job.
  #               NOTE: setting to false will perform inline without a throttler.
  #               If the entity you're clearing has an unknown amount of Abilities
  #               call clear! directly to get a throttled delete.
  #
  # Returns participant.
  def self.clear(participant, async: true)
    return participant if !participant.ability_delegate

    original_participant = participant
    participant          = participant.ability_delegate

    ability_id   = participant.ability_id
    ability_type = participant.ability_type

    if async
      ClearAbilitiesJob.perform_later(ability_id, ability_type)
    else
      begin
        clear!(ability_id, ability_type, throttle_writes: false)
      ensure
        GitHub.dogstats.increment("abilities.clear.sync")
      end
    end

    original_participant
  end

  # Public: Remove any abilities involving an actor and/or subject.
  #
  # ability_id   - The id of the Ability::Participant
  # ability_type - The type of the Ability::Participant
  #
  # Returns nothing.
  def self.clear!(ability_id, ability_type, throttle_writes: true)
    PermissionCache.clear

    GitHub.dogstats.distribution_time("ability.clear.latency") do
      direct_bindings = {
        id: ability_id,
        type: ability_type,
        direct: Ability.priorities[:direct],
      }

      direct = Arel.sql <<-SQL, **direct_bindings
          SELECT id FROM abilities
          WHERE (actor_id = :id AND actor_type = :type)
          OR    (subject_id = :id AND subject_type = :type)
          AND priority = :direct
      SQL

      Ability.connection.select_values(direct).each_slice(Ability::BATCH_SIZE) do |slice|
        delete_dependent_abilities_for!(slice)

        if throttle_writes
          throttle { where(id: slice).delete_all }
        else
          where(id: slice).delete_all
        end
      end
    end
  end

  # Internal: Queue a job to delete abilities referencing any of the specified
  # abilities through the indirect grant ancestry information in
  # parent_id and/or grandparent_id
  #
  # ability_ids - IDs of the abilities whose dependent abilities we want to
  #               delete.
  #
  # Returns nothing.
  def self.delete_dependent_abilities_for(ability_ids)
    ids = [ability_ids].flatten.compact
    return if ids.empty?

    DeleteDependentAbilitiesJob.perform_later(ids)
  end

  # Internal: Delete abilities referencing any of the specified abilities through
  # the indirect grant ancestry information in parent_id and/or grandparent_id
  #
  # ability_ids - IDs of the abilities whose dependent abilities we want to
  #               delete.
  #
  # Returns nothing.
  def self.delete_dependent_abilities_for!(ability_ids)
    ids = [ability_ids].flatten.compact
    return if ids.empty?

    # abilities w/ parent_id's can be for forks or nested teams
    dependent_ids = ActiveRecord::Base.connected_to(role: :reading) do
      ids.each_with_object([]) do |id, arr|
        arr << Ability.connection.select_values(Arel.sql(<<-SQL, id: id, direct: priorities[:direct]))
          SELECT id FROM abilities
          WHERE parent_id = :id
          AND priority <= :direct
        SQL
      end.flatten
    end

    return if dependent_ids.empty?

    dependent_ids.each_slice(Ability::BATCH_SIZE) do |slice|
      throttle do
        Ability.connection.delete(Arel.sql(<<-SQL, ids: slice))
          DELETE FROM abilities WHERE id IN (:ids)
        SQL
      end
    end
    GitHub.dogstats.count "ability.revoked.dependent", dependent_ids.size
  end

  # Public: Grant an actor the ability to perform an action on a subject.
  #
  # actor   - An Ability::Actor
  # action  - A :read, :triage, :write, :maintain, or :admin Symbol
  # subject - An Ability::Subject
  # grantor: The actor granting the ability
  #
  # Returns the granted Ability.
  def self.grant(actor, action, subject, grantor: nil, role_name: nil)
    actor   = actor.ability_delegate
    subject = subject.ability_delegate

    actor.can_be_granted_permission_over!(subject, action)
    PermissionCache.clear

    # Handle granting/revoking FGP roles on organization repositories
    if subject.is_a?(Repository) && subject.owner&.organization?
      # clear out any old roles before granting a new one
      revoke_role!(actor, subject)
      if !Ability.valid_action?(action.to_sym)
        grant_role!(actor, subject, action.to_s, grantor: grantor)
        action = nil
      end
    end

    return unless action

    GitHub.dogstats.distribution_time("ability.grant.latency") do
      Ability::Grant.new(actor, action, subject, grantor: grantor, role_name: role_name).apply
    end
  end

  # Public: Grant an actor the ability to perform an action on a subject.
  #
  # actors  - An Ability::Actor
  # action  - A :read, :triage, :write, :maintain, or :admin Symbol
  # subject - An Ability::Subject
  # grantor: The actor granting the ability
  #
  # Returns the array of granted Ability. Elements can be nil.
  def self.bulk_grant(actors, action, subject, grantor: nil)
    actors  = actors.map { |actor| actor.ability_delegate }
    subject = subject.ability_delegate

    actors.each { |actor| actor.can_be_granted_permission_over!(subject, action) }
    PermissionCache.clear

    actors.map do |actor|
      # Handle granting/revoking FGP roles on organization repositories
      if subject.is_a?(Repository) && subject.owner&.organization?
        # clear out any old roles before granting a new one
        revoke_role!(actor, subject)
        if !Ability.valid_action?(action.to_sym)
          grant_role!(actor, subject, action.to_s, grantor: grantor)
          action = nil
        end
      end

      next unless action

      GitHub.dogstats.distribution_time("ability.grant.latency") do
        Ability::Grant.new(actor, action, subject, grantor: grantor).apply
      end
    end
  end

  # Public: Revoke an actor's direct ability to perform an action on a subject.
  #
  # actor      - An Ability::Actor
  # subject    - An Ability::Subject
  # background - Optional. Delete dependent abilities in a background job unless false.
  #
  # Returns nothing.
  def self.revoke(actor, subject, background: true)
    actor   = actor.ability_delegate
    subject = subject.ability_delegate

    PermissionCache.clear
    GitHub.dogstats.distribution_time("ability.revoke.dist", tags: ["batch:false"]) do
      return unless ability = Ability.where(
        actor_id: actor.ability_id,
        actor_type: actor.ability_type,
        subject_id: subject.ability_id,
        subject_type: subject.ability_type,
        priority: Ability.priorities[:direct],
      ).first

      transaction do
        delete_dependent_abilities_for!([ability.id]) unless background
        ability.destroy
        GitHub.dogstats.increment "ability.revoked.direct"
      end
    end

    nil
  end

  # Public: Destroy the given abilities.
  #
  # abilities - An Ability relation
  #
  # Returns nothing.
  def self.revoke_abilities(abilities)
    return unless abilities.present?

    PermissionCache.clear

    GitHub.dogstats.distribution_time("ability.revoke.latency", tags: ["batch:true"]) do
      transaction do
        abilities.destroy_all
        GitHub.dogstats.increment "ability.revoked.direct"
      end
    end

    nil
  end

  # Public: Delete the given abilities with required callbacks
  #
  # abilities - An Ability relation
  #
  # Returns nothing.
  def self.delete_all_abilities(ability_records)
    return unless ability_records.present?
    raise ArgumentError, "delete_all_abilities cannot be executed on Repository abilities" if ability_records.any? { |a| a.subject_type == "Repository" }

    PermissionCache.clear

    ability_records.map(&:id).each_slice(100) do |ids|
      with_write do
        begin
          Ability.delete_dependent_abilities_for(ids)

          abilities = Ability.where(id: ids)

          abilities.each do |ability|
            ability.instrument_revoke
          end

          abilities.delete_all
        rescue ActiveRecord::StatementInvalid => error
          Failbot.report(error, :msg => "Failed to delete_all_abilities", "gh.ability.ids" => ids)
          raise error
        end
      end
    end
  end

  # Public: Adds an index hint
  #
  # index - the index to suggest
  #
  # Returns nothing.
  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end

  # Public: The String action name for this ability.
  #
  # Returns a String.
  def action_name
    action.to_s
  end

  # Internal: Compare two abilities' permissions and priority.
  # Mirrors the "prioritized" scope.
  #
  # other - Another Ability
  #
  # Returns the usual tri-state. See Comparable for details.
  def <=>(other)
    return nil unless other.is_a?(Ability)

    [Ability.actions[action], Ability.priorities[priority]] <=>
      [Ability.actions[other.action], Ability.priorities[other.priority]]
  end

  # Internal: Does this Ability have an action that's equal or better?
  #
  # other_action - A :read, :write, or :admin Symbol
  #
  # Returns true or false.
  def can?(other_action)
    Ability.actions[action] >= Ability.actions[other_action]
  end

  # Internal: Does this Ability have an action that's equal or better?
  #
  # action - A :read, :write, or :admin Symbol
  #
  # Returns true or false.
  def self.can_at_least?(action, permission)
    return false if permission.nil? || self.actions[permission].nil?
    self.actions[permission] >= self.actions[action]
  end

  # Internal: Delete any abilities referencing this ability as an indirect
  # parent or grandparent.
  #
  # This is used when revoking direct grants to revoke related indirect grants.
  #
  # Returns self.
  def delete_dependent_abilities
    self.class.delete_dependent_abilities_for self.id
    self
  end

  # Public:
  #
  # Returns a more readable representation of the Ability
  def to_s
    type = if !id && priority == :indirect
      "inferred indirect"
    elsif id && priority == :indirect
      "id=#{id}, materialized indirect"
    else
      "id=#{id} #{priority}"
    end

    actor   = "#{actor_type} #{self.actor}"   rescue "missing actor (#{actor_type}##{actor_id})"
    subject = "#{subject_type} #{self.subject}" rescue "missing subject (#{subject_type}##{subject_id})"

    str = "Ability #{type}: #{actor} has #{action} permission over #{subject}."
    str += " Parent is: ##{parent_id}" if parent_id != 0
    str
  end

  # Internal: Base payload for instrumentation events
  def event_payload
    {
      action:               action.to_sym,
      priority:             priority.to_sym,
      ability_actor_id:     actor_id,
      ability_actor_type:   actor_type,
      ability_subject_id:   subject_id,
      ability_subject_type: subject_type,
    }
  end

  # Internal: callback for instrumentation
  def instrument_grant
    instrument :grant, event_payload.merge(grantor_id: grantor_id, role_name: role_name&.to_sym)
  end

  # Internal: callback for instrumentation
  def instrument_revoke
    instrument :revoke
  end

  # Internal: Grants a role on a subject for an actor.
  # Only triage/maintain (reserved roles) and custom roles are granted through here.
  #
  # Returns a RoleGrantResult.
  def self.grant_role!(actor, subject, role_name, grantor: nil)
    role = if Role::RESERVED_NAMES.include?(role_name)
      Role.preset_by_name(role_name)
    else
      RepositoryRole.custom_role_by_name(role_name, org: subject.owner)
    end

    Permissions::Granters::RoleGranter.new(
      actor: actor, target: subject, role: role, grantor: grantor
    ).grant!
  end

  # Internal: Revokes role on a subject for an actor.
  #
  # Returns a RoleGrantResult.
  def self.revoke_role!(actor, subject)
    if subject.is_a?(Repository) && subject.owner&.organization?
      Permissions::Granters::RoleGranter.new(
        actor: actor, target: subject,
      ).revoke_if_exists!
    end
  end

  # Internal: Revokes role on a subject for an actor.
  #
  # Returns a RoleGrantResult.
  def revoke_role!
    if subject_type == "Repository" && subject.owner&.organization?
      Permissions::Granters::RoleGranter.new(
        actor: actor, target: subject,
      ).revoke_if_exists!
    end
  end
  alias :revoke_remaining_role! :revoke_role!
end
