# typed: false
# frozen_string_literal: true

module User::AbilityDependency
  extend ActiveSupport::Concern

  include Ability::Actor
  include Ability::Subject

  def ability_description
    "@#{display_login}"
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def adminable_by?(actor)
    if actor.nil?
      false
    elsif user? && actor.user? && actor.id != id
      false
    else
      super # hit Ability::Subject#adminable_by?
    end
  end

  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    actor = actor.ability_delegate

    return Promise.resolve(false) if !actor.is_a?(User) || actor.new_record?

    super
  end

  # Internal: Because we don't allow grants where a user is the subject, a user
  # cannot be used as an Abilities connector.
  def connector?
    false
  end

  # Internal: Disallow grants where a user is the subject.
  def grant?(actor, action)
    false
  end

  def can_set_interaction_limits?(actor)
    async_can_set_interaction_limits?(actor).sync
  end

  def async_can_set_interaction_limits?(actor)
    Promise.resolve(actor == self)
  end

  def async_can_read_interaction_limits?(actor)
    async_can_set_interaction_limits?(actor)
  end

  def can_read_interaction_limits?(actor)
    async_can_read_interaction_limits?(actor).sync
  end
end
