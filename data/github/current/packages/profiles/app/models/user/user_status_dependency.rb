# typed: false
# frozen_string_literal: true

module User::UserStatusDependency
  extend ActiveSupport::Concern

  included do
    has_one :user_status
  end

  # Public: Clears the user's status if it is tied to particular organization.
  #
  # org - an Organization
  #
  # Returns nothing.
  def destroy_org_restricted_user_status(org)
    if org && user_status&.organization == org
      with_write { user_status.destroy }
    end
  end

  # Public: Returns the user_status if expires_at is in the future
  #
  # Returns UserStatus
  def async_user_status_when_not_expired
    async_user_status.then do |user_status|
      user_status unless user_status&.expired?
    end
  end

  def user_status_when_not_expired
    async_user_status_when_not_expired.sync
  end

  # The status visible to the passed viewer
  #
  # viewer - the viewer to return a status for
  #
  # Returns a UserStatus
  def async_status_visible_to(viewer)
    async_user_status_when_not_expired.then do |status|
      status&.async_readable_by?(viewer).then do |is_visible|
        status if is_visible
      end
    end
  end

  def status_visible_to(viewer)
    async_status_visible_to(viewer).sync
  end

  # Public: Determines if the user considers themselves to be busy and may
  # have a delayed response to mentions in issue comments.
  #
  # viewer - The User who would like to know if this user is busy.
  #
  # Returns true if the user is busy right now.
  def busy?(viewer:)
    return false if !user_status
    return false if user_status.expired?
    return false if !user_status.limited_availability?
    user_status.async_readable_by?(viewer).sync
  end
end
