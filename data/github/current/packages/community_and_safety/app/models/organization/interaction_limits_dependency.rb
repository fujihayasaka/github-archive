# typed: false
# frozen_string_literal: true

module Organization::InteractionLimitsDependency
  extend ActiveSupport::Concern

  # Public: Can a user read interaction limits in this organization?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_read_interaction_limits?(actor)
    return Promise.resolve(false) unless actor.present?

    resources.organization_administration.async_readable_by?(actor).then do |is_readable|
      next true if is_readable
      async_moderator?(actor)
    end
  end

  def can_read_interaction_limits?(actor)
    async_can_read_interaction_limits?(actor).sync
  end

  # Public: Can a user set interaction limits in this organization?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_set_interaction_limits?(actor)
    return Promise.resolve(false) unless actor.present?

    resources.organization_administration.async_writable_by?(actor).then do |is_adminable|
      next true if is_adminable
      async_moderator?(actor)
    end
  end

  def can_set_interaction_limits?(actor)
    async_can_set_interaction_limits?(actor).sync
  end
end
