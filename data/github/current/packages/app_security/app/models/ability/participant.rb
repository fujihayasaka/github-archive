# typed: false
# frozen_string_literal: true

# Public: An Actor or Subject in the Ability universe. This class deals with
# identity, providing default `ability_id` and `ability_type` implementations.
module Ability::Participant
  extend ActiveSupport::Concern

  included do
    after_destroy(:clear_abilities, if: :clear_abilities_per_destroyed_record?) if respond_to?(:after_destroy)
  end

  def clear_abilities
    Ability.clear self
  end

  # By default abilities are cleared when any ActiveRecord class mixes-in this
  # module. Override this behavior at the top of the to return false if a custom logic for permission
  # removal is implemented
  def clear_abilities_per_destroyed_record?
    true
  end

  # Public: A pretty description String for this model, including both type
  # and identity. It's ability_type and ability_id by default.
  def ability_description
    "#{ability_type} #{ability_id}"
  end

  # Public: A Integer identifier for this model. Default is id.
  def ability_id
    ability_delegate.id
  end

  # Public: A String type for this model. Default is self.class.name.
  def ability_type
    ability_delegate.class.name
  end

  # Internal: Is this participant an actor? Default is false.
  def actor?
    false
  end

  # Public whether the participant is able to participate
  def participates?
    ability_delegate.present?
  end

  # Internal: Is this participant a connector?
  def connector?
    actor? && subject?
  end

  # Internal: Is this participant a subject? Default is false.
  def subject?
    false
  end

  # Internal: Participates in abilities on behalf of this model. Default is self.
  def ability_delegate
    self
  end

  # overridden by participants: teams, projects, and repos
  # which can have owning organizations
  #
  # Returns an Ability::Participant or nil
  def owning_organization_id; end
  def owning_organization_type; end
end
