# typed: true
# frozen_string_literal: true

class AchievementProgression < ApplicationRecord::Domain::Achievements
  VISIBILITY_ATTRIBUTE_MAPPING = {
    PUBLIC: :public_count,
    PRIVATE: :private_count,
  }.freeze

  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user

  validates :user_id, presence: true
  validates(
    :achievable_slug,
    inclusion: { in: Achievable.known_slugs },
    presence: true,
    uniqueness: { scope: :user_id },
  )

  def achievable
    Achievable.with_slug(achievable_slug)
  end

  def to_h
    {
      public_count: public_count,
      private_count: private_count,
    }
  end

  def increment_count!(visibility)
    attr = VISIBILITY_ATTRIBUTE_MAPPING[visibility]

    increment!(attr)
  end
end
