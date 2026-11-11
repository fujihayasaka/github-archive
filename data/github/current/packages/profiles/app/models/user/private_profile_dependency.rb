# typed: false
# frozen_string_literal: true

module User::PrivateProfileDependency
  extend ActiveSupport::Concern

  included do
    scope :with_visible_profiles_for, ->(viewer) do
      if viewer.present?
        where("(id = ? OR private_profile = 0)", viewer.id)
      else
        where(private_profile: false)
      end
    end
  end

  # Public: whether this user's profile should be private for the specified viewer.
  #
  # Returns a Boolean
  def private_profile_for?(viewer)
    self.private_profile? && self != viewer
  end
end
