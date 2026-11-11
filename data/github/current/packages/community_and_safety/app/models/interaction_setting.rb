# typed: true
# frozen_string_literal: true

# Contains user settings related to interactions with other users
class InteractionSetting < ApplicationRecord::Domain::Users
  include ::Users::BelongsToUser
  belongs_to_user_via_domain required: true
  destroy_in_background_with :user
  validate :ensure_user_is_not_organization, on: :create

  private

  def ensure_user_is_not_organization
    errors.add(:user, "cannot be an organization") if user&.organization?
  end
end
