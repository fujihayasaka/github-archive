# typed: false
# frozen_string_literal: true

class UserMetadata < ApplicationRecord::Domain::Users
  belongs_to :user

  validates :user, presence: true, uniqueness: true

  # Public: Interpret the serialized slug attributes as a list of Achievable slugs and corresponding tiers.
  #
  # visibility - Symbol (:PUBLIC or :PRIVATE) indicating which set of slugs to return.
  #
  # Returns an Array of [Achievable, Integer] pairs corresponding to the achievables of this user's unlocked
  # Achievements, ordered with most recently unlocked first. Unrecognized slugs are ignored.
  def achievables_and_tiers(visibility:)
    slugs = visibility == :PRIVATE ? achievement_private_slugs : achievement_public_slugs
    (slugs || "").split(",").flat_map do |slug_and_tier|
      slug, tier = slug_and_tier.split(":")
      achievable = Achievable.with_slug(slug)
      if achievable
        [[achievable, tier.to_i]]
      else
        []
      end
    end
  end

  def has_mars_badge?
    return false unless user

    user.profile_highlights.exists?(highlight_type: :nasa_2020, eligible: true, hidden: false)
  end
end
