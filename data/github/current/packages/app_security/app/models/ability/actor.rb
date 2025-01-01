# typed: false
# frozen_string_literal: true

# Public: Something that's allowed to perform actions on a subject. The most
# common GitHub actor is a User, but Organizations and Teams are actors too.
module Ability::Actor
  extend ActiveSupport::Concern

  include Ability::Participant
  include Permissions::Participant

  include Scientist

  # Public: A prioritized collection of things this actor can do.
  # Ability scopes can be used to narrow this collection further.
  #
  # ids   - Optionally restrict the ability_id of subjects.
  # types - Optionally restrict the ability_type of subjects.
  #
  # Returns an Array of abilities
  def abilities(ids: [], types: [])
    actor = ability_delegate
    return [] if actor.nil?

    ids   = Array(ids)
    types = Array(types)

    models = Permissions::QueryRouter.data_sources_for_actor(actor).flat_map do |source|
      query_bindings = {
        table_name:    source[:table_name],
        actor_type:    actor.ability_type,
        actor_id:      actor.ability_id,
        subject_ids:   ids,
        subject_types: types,
        direct:        Ability.priorities[:direct],
        indirect:      Ability.priorities[:indirect],
      }

      # actor query
      actor_sql = <<-SQL
        SELECT id,
            actor_id, actor_type, action, subject_id, subject_type,
            priority, created_at, updated_at, parent_id, NULL grandparent_id
          FROM   :table_name
          WHERE  actor_id   = :actor_id
          AND    actor_type = :actor_type
          AND    priority   = :direct
      SQL

      actor_sql += "AND subject_id IN (:subject_ids)"     unless ids.empty?
      actor_sql += "AND subject_type IN (:subject_types)" unless types.empty?
      actor_sql += "ORDER BY action DESC, priority DESC"

      # ancestors query
      ancestor_sql = <<-SQL
        SELECT NULL AS id,
          /* abilities-join-audited */
          grandparent.actor_id, grandparent.actor_type,
          parent.action,
          parent.subject_id, parent.subject_type,
          :indirect AS priority,
          greatest(parent.created_at, grandparent.created_at) AS created_at,
          greatest(parent.updated_at, grandparent.updated_at) AS updated_at,
          parent.id AS parent_id, grandparent.id AS grandparent_id
        FROM   :table_name parent
        JOIN   :table_name grandparent
        ON     grandparent.subject_type = parent.actor_type
        AND    grandparent.subject_id   = parent.actor_id
        WHERE  grandparent.actor_id     = :actor_id
        AND    grandparent.actor_type   = :actor_type
        AND    parent.priority          = :direct
        AND    grandparent.priority     = :direct
      SQL
      ancestor_sql += "AND parent.subject_id IN (:subject_ids)"     unless ids.empty?
      ancestor_sql += "AND parent.subject_type IN (:subject_types)" unless types.empty?
      ancestor_sql += "ORDER BY action DESC, priority DESC"

      GitHub.dogstats.distribution_time("ability.actor.abilities.dist", tags: ["query_type:#{source[:table_name]}"]) do
        Ability.find_by_sql(Arel.sql(actor_sql, **query_bindings)) + Ability.find_by_sql(Arel.sql(ancestor_sql, **query_bindings))
      end
    end

    de_dupe(models)
  end

  # Public: What can I do to this?
  #
  # subject - An Ability::Subject
  #
  # Returns an Ability or nil.
  def ability(subject)
    Authorization.service.most_capable_ability_between(actor: self, subject: subject)
  end

  # Naturally. See Ability::Participant.
  def actor?
    true
  end

  def can_be_granted_abilities?
    true
  end

  private

  # Private: de-duplicates a list of Ability records based on attributes other
  # than database ID.
  #
  # models - Array of Ability models.
  #
  # Returns an Array of unique Ability models.
  def de_dupe(models)
    models.uniq do |ability|
      [
        ability.actor_id,
        ability.actor_type,
        ability.subject_id,
        ability.subject_type,
        ability.action,
        ability.priority,
        ability.parent_id,
      ]
    end
  end
end
