# typed: false
# frozen_string_literal: true

module User::AbilityDependency
  extend ActiveSupport::Concern

  include Ability::Actor
  include Ability::Subject

  def ability_description
    "@#{display_login}"
  end

  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    actor = actor.ability_delegate

    if !actor.is_a?(User) || actor.new_record?
      return Promise.resolve(false)
    end

    case action
    when :read
      if self.organization?
        # In order to account for indirect access to an organization, we need
        # to use the membership check instead of the direct abilities query.
        #
        # Similar overrides have been done for models such as
        # Repository via #async_permit?.
        self.async_member?(actor)
      else
        Promise.resolve(self == actor)
      end
    when :admin
      if actor.nil?
        Promise.resolve(false)
      elsif user? && actor.user? && actor.id != id
        Promise.resolve(false)
      else
        super # hit Ability::Subject#async_permit?
      end
    else
      super
    end
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
