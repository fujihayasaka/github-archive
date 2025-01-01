# typed: true
# frozen_string_literal: true

#
class Ability::Grant::ApplyToAncestors
  include Ability::Grant::ApplyAbilities

  def self.execute(ability, subject)
    new(ability, subject).execute
  end

  attr_reader :ability, :subject

  def initialize(ability, subject)
    @ability = ability
    @subject = subject
  end

  def execute
    return unless ability.persisted?
    ancestor_ids = subject.ancestor_ids

    actor_id = ability.actor_id
    actor_type = ability.actor_type
    action = Ability.actions[:read]
    subject_type = ability.subject_type
    priority = Ability.priorities[:indirect]
    parent_id = ability.id
    now = GitHub::SQL::ArelLiterals::NOW

    rows = ancestor_ids.map do |ancestor_id|
      [
       actor_id,
       actor_type,
       action,
       ancestor_id,
       subject_type,
       priority,
       parent_id,
       now,
       now,
      ]
    end

    apply_abilities(rows, stats_key: :indirect_ancestors)
  end
end
