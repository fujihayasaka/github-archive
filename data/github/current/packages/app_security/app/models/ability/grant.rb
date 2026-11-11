# typed: false
# frozen_string_literal: true

# Internal: A potential ability.
class Ability::Grant

  THROTTLE_RETRIES = 3

  attr_reader :actor, :action, :subject, :grantor, :role_name

  # Grants an actor access to a subject
  #
  # actor - the actor
  # action - the level of access the actor will have over the subject
  # subject - the subject this actor will end up having access to
  # grantor: The actor granting the ability
  #
  def initialize(actor, action, subject, grantor: nil, role_name: nil)
    if actor.connector? && subject.connector?
      raise "#{actor.ability_type} -> #{subject.ability_type} grants aren't allowed"
    end

    @actor     = actor
    @action    = action
    @subject   = subject
    @grantor   = grantor
    @role_name = role_name || action
  end

  # Public: Grant actor the ability to perform action on subject.
  def apply
    ability = Ability.new(
      actor_id: actor.ability_id,
      actor_type: actor.ability_type,
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
      action: action,
      priority: :direct,
    )

    ability.grantor_id = grantor&.id
    ability.role_name = role_name
    ability_saved = false
    old_action = nil

    Ability.transaction do
      begin
        ability.save!
        ability_saved = true

        self.class.apply_abilities_to_ancestors(ability, subject)
      rescue ActiveRecord::RecordNotUnique
        GitHub.dogstats.increment("ability.create_or_update", tags: ["event:not_unique_exception"])
        retried = false unless defined?(retried)

        # If an ability has been created in another transaction in the midst
        # of the begin-rescue block execution, we prevent the racey behavior.
        if existing_ability = find_existing_direct_ability(actor, subject)
          old_action = existing_ability.action
          existing_ability.action = action

          if existing_ability.changed?
            GitHub.dogstats.increment("ability.create_or_update", tags: ["event:changed"])
            existing_ability.save!
            ability_saved = true

            self.class.apply_abilities_to_ancestors(existing_ability, subject, old_action)
          end

          ability = existing_ability
        elsif retried
          GitHub.dogstats.increment("ability.create_or_update", tags: ["event:retried"])
          # Reraise if we've already retried.
          raise
        else
          GitHub.dogstats.increment("ability.create_or_update", tags: ["event:retry"])
          # If we haven't retried, attempt to create the ability again.
          retried = true
          retry
        end
      end
    end

    GitHub.dogstats.increment("ability.granted.direct")

    ability
  end

  # apply the materialized, indirect abilities to ancestors (in the case of nested teams)
  def self.apply_abilities_to_ancestors(ability, subject, old_action = nil)
    old_action = old_action&.to_sym
    # added to a team within a hierarchy
    return unless old_action.nil? && subject.ancestors?
    ApplyToAncestors.execute(ability, subject)
  end

  # Internal: Find existing direct ability, if one exists.
  # Returns an Ability record.
  def find_existing_direct_ability(actor, subject)
    return unless actor && subject
    Ability.where(
      actor_id: actor.ability_id,
      actor_type: actor.ability_type,
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
      priority: Ability.priorities[:direct],
    ).first
  end
end
