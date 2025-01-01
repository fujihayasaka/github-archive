# typed: true
# frozen_string_literal: true

# Public: An entity that permits some actors to perform actions. The most
# common GitHub subjects are Repositories, Organizations, and Teams.
module Ability::Subject
  extend ActiveSupport::Concern
  extend T::Helpers

  include Ability::Participant
  include Scientist

  requires_ancestor { Kernel }

  class GrantPermissionError < StandardError ; end

  # Public: actor ids with permissions (ability can be inherited or direct) on this subject.
  #
  # type:       - Required Class or class name to restrict the actors retrieved.
  # min_action: - Optional minimum action to restrict which grants are examined.
  #               Default is :read.
  #
  # Returns an Array of ids.
  def actor_ids(type:, min_action: :read, actor_ids_filter: nil)
    subject_actor_ids(type:, min_action:, actor_ids_filter:)
  end

  def subject_actor_ids(type:, min_action: :read, actor_ids_filter: nil)
    unless Ability.actions[min_action]
      raise ArgumentError, "unknown min_action #{min_action.inspect}"
    end

    return [] if actor_ids_filter && actor_ids_filter.empty?

    sql_bindings = {
      actor_type: type,
      actor_ids_filter: actor_ids_filter,
      min_action: Ability.actions[min_action],
      admin: Ability.actions[:admin],
      subject_id: ability_id,
      subject_type: ability_type,
      direct: Ability.priorities[:direct],
      indirect: Ability.priorities[:indirect],
      owning_organization_type: owning_organization_type,
      owning_organization_id: owning_organization_id,
    }

    sql = Arel.sql <<-SQL, **sql_bindings
      SELECT actor_id

      /* abilities-join-audited */
      FROM   abilities
      WHERE  actor_type   = :actor_type
      AND    action      >= :min_action
      AND    subject_id   = :subject_id
      AND    subject_type = :subject_type
      AND    priority     <= :direct
    SQL

    if actor_ids_filter
      sql += Arel.sql <<-SQL, **sql_bindings
        AND    actor_id IN (:actor_ids_filter)
      SQL
    end

    sql += Arel.sql <<-SQL, **sql_bindings
      UNION ALL

      SELECT grandparent.actor_id
      FROM   abilities parent
      JOIN   abilities grandparent
      ON     grandparent.subject_type = parent.actor_type
      AND    grandparent.subject_id   = parent.actor_id
      WHERE  parent.priority          <= :direct
      AND    grandparent.priority     <= :direct
      AND    grandparent.actor_type   = :actor_type
      AND    parent.action           >= :min_action
      AND    parent.subject_id        = :subject_id
      AND    parent.subject_type      = :subject_type
    SQL

    if actor_ids_filter
      sql += Arel.sql <<-SQL, **sql_bindings
        AND    grandparent.actor_id IN (:actor_ids_filter)
      SQL
    end

    if owning_organization_id.present?
      sql += Arel.sql <<-SQL, **sql_bindings
      UNION ALL

      SELECT ab.actor_id
      FROM   abilities ab
      WHERE  ab.subject_type = :owning_organization_type
      AND    ab.subject_id   = :owning_organization_id
      AND    ab.actor_type   = :actor_type
      AND    ab.action       = :admin
      AND    ab.priority     = :direct
      SQL

      if actor_ids_filter
        sql += Arel.sql <<-SQL, **sql_bindings
          AND    ab.actor_id IN (:actor_ids_filter)
        SQL
      end
    end

    Ability.connection.select_values(sql).uniq
  end

  # Internal: The list of ancestor ids exposed by this subject.
  # An ancestor is of the same type of the subject.
  def ancestor_ids
    []
  end

  # Internal: The relation of ancestors exposed by this subject.
  # An ancestor is of the same type of the subject.
  def ancestors
    []
  end

  def ancestors?
    false
  end

  # Internal: An Array of child subjects that should be included when
  # cascading admin ability grants on a parent subject. For example, an
  # Organization returns its teams and repositories.
  #
  # The Ability system only needs `ability_type` and `ability_id`, so limiting
  # the `SELECT` clause of queries here can be useful.
  def dependents
    []
  end

  # Internal: Does this subject expose dependents?
  def dependents?
    false
  end

  # Internal: Give direct admin actors on this subject admin on the given dependent as well.
  def dependent_added(dependent)
  end

  # Internal: Revoke direct admin actors on this subject from the dependent.
  def dependent_removed(dependent)
  end

  # Internal: Give an actor the ability to perform an action on this subject.
  #
  # actor  - An Ability::Actor
  # action - A :read, :write, or :admin Symbol
  # grantor: The actor granting the ability
  #
  # Returns the new Ability.
  def grant(actor, action, grantor: nil)
    return unless actor.can_be_granted_abilities?
    unless grant?(actor, action)
      raise "#{ability_description} won't grant #{action} to #{actor.ability_description}"
    end
    Ability.grant(actor, action, self, grantor: grantor)
  end

  # This is a method for internal use only. Define and use an explicit domain
  # method instead of trying to call this directly, e.g. Team#add_member(user).
  private :grant

  # Internal: Give an actor the ability to perform an action on multiple subjects.
  #
  # actors - An array of Ability::Actor
  # action - A :read, :write, or :admin Symbol
  # grantor: The actor granting the ability
  # skip_revoke: bool if revoke should be skipped. Only for unafilliated users
  #
  # Returns the array of granted Ability.
  def bulk_grant(actors, action, grantor: nil, skip_revoke: false)
    valid_actors = actors.map do |actor|
      next if !actor.can_be_granted_abilities?

      # The exception is going to be handled on a higher level, since we want to fail the whole
      # batch and switch to individual grants.
      unless grant?(actor, action)
        raise GrantPermissionError, "#{ability_description} won't grant #{action} to #{actor.ability_description}"
      end

      actor
    end

    Ability.bulk_grant(valid_actors, action, self, grantor: grantor, skip_revoke: skip_revoke)
  end

  # Internal: Give an actor the ability to perform an action on multiple subjects.
  # importantly does not attempt to revoke existing ability records
  #
  # actors - An array of Ability::Actor
  # action - A :read, :write, or :admin Symbol
  # grantor: The actor granting the ability
  #
  # Returns the array of granted Ability.
  def bulk_grant_unafilliated(actors, action, grantor: nil)
    bulk_grant(actors, action, grantor: grantor, skip_revoke: true)
  end

  # This is a method for internal use only. Define and use an explicit domain
  # method instead of trying to call this directly, e.g. Team#add_member(user).
  private :bulk_grant

  # Public: Does the given actor have read ability on this subject?
  def readable_by?(actor)
    permit?(actor, :read)
  end

  # Public: Does the given actor have read ability on this subject?
  #
  # Returns Promise<bool>
  def async_readable_by?(actor)
    async_permit?(actor, :read)
  end

  # Public: Does the given actor have write ability on this subject?
  def writable_by?(actor)
    permit?(actor, :write)
  end

  # Public: Does the given actor have write ability on this subject?
  #
  # Returns Promise<bool>
  def async_writable_by?(actor)
    async_permit?(actor, :write)
  end

  # Public: Does the given actor have admin ability on this subject?
  sig { params(actor: T.untyped).returns(T::Boolean) }
  def adminable_by?(actor)
    permit?(actor, :admin)
  end

  # Public: Does the given actor have admin ability on this subject?
  #
  # Returns Promise<bool>
  def async_adminable_by?(actor)
    async_permit?(actor, :admin)
  end

  # Internal: A hook. Will this subject permit actor to perform action?
  # Default behavior prohibits actors who are connectors since we don't have
  # any team-on-team or team-on-org action.
  def grant?(actor, action)
    !(connector? && actor.connector?)
  end

  # Internal: revoke the direct ability between an actor and this subject.
  def revoke(actor, background: true)
    Ability.revoke(actor, self, background: background)
  end

  # Internal: revoke a list of direct abilities between a list of actors and this subject.
  def bulk_revoke(actor_ids:, actor_type:, background: true)
    Ability.bulk_revoke(
      actor_ids: actor_ids,
      actor_type: actor_type,
      subject_ids: [ability_id],
      subject_type: ability_type,
      background: background
    )
  end

  # Internal use only. Define and use an explicit domain method instead of
  # calling this directly, e.g. Team#remove_member.
  private :revoke

  # Internal: Naturally. See Ability::Participant.
  def subject?
    true
  end

  # Internal: is an actor allowed to perform this action?
  #
  # actor  - An Ability::Actor
  # action - A :read, :write, or :admin Symbol
  #
  # Override this method to add constraints beyond what abilities tracks, such
  # as type-checking or public/private checks. See Repository#permit? and
  # Team#permit? for examples.
  #
  # Returns true or false.
  def permit?(actor, action)
    Ability.can?(actor, action, self)
  end

  # Internal: is an actor allowed to perform this action?
  #
  # Same as the permit? method above, but returns Promise<bool>
  def async_permit?(actor, action)
    Ability.async_can?(actor, action, self)
  end

  # This is a method for internal use only. Define and use an explicit domain
  # method for wrapping this method instead of trying to call this directly,
  # e.g. Repository#pullable_by?
  private :permit?
end
