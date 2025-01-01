# typed: true
# frozen_string_literal: true

module Organization::ModerationDependency
  extend ActiveSupport::Concern

  # Public: The instance of the moderation settings object for this organization.
  #
  # Returns an Organization::Moderation.
  def moderation
    @moderation ||= Organization::Moderation.new(self)
  end

  # Public: Indicates if an actor is a moderator for this organization.
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def moderator?(actor)
    moderation.moderator?(actor)
  end

  # Public: Indicates if an actor is a moderator for this organization.
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def async_moderator?(actor)
    moderation.async_moderator?(actor)
  end

  # Public: Get a list of all moderators for this organization.
  #
  # Returns an Array[User|Team].
  def moderators
    @moderators ||= moderation.moderators
  end
end
