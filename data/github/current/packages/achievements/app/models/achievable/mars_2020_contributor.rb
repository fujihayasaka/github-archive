# typed: true
# frozen_string_literal: true

class Achievable
  class Mars2020Contributor < ::Achievable
    REPO_LIMIT = 3
    LINK_TEXT = "Mars 2020 Helicopter Mission"
    LINK_HREF = "https://github.com/readme/nasa-ingenuity-helicopter"

    define_tier

    dynamic_unlocking_event(model_type: "AchievementRepositoryList") do |achievements|
      GitHub::PrefillAssociations.prefill_associations(achievements, { user: :profile_highlights })
      achievements.index_with do |achievement|
        next AchievementRepositoryList.none unless achievement.user
        repos = achievement.user
          .profile_highlights
          .select(&:displayable?)
          .find(&:nasa_2020?)
          &.top_repositories(limit: REPO_LIMIT + 1)
        AchievementRepositoryList.new(repositories: repos || [])
      end
    end

    mobile_background_color "#64012E"

    def self.display_name
      "Mars 2020 Contributor"
    end

    def self.enabled?(_)
      true
    end

    def self.has_rounded_badge_variant?
      true
    end
  end
end
