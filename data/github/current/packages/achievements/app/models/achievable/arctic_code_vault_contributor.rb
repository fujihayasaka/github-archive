# typed: true
# frozen_string_literal: true

class Achievable
  class ArcticCodeVaultContributor < ::Achievable
    REPO_LIMIT = 3
    LINK_TEXT = "2020 GitHub Archive Program"
    LINK_HREF = "https://archiveprogram.github.com"

    define_tier

    dynamic_unlocking_event(model_type: "AchievementRepositoryList") do |achievements|
      GitHub::PrefillAssociations.prefill_associations(achievements, { user: :user_metadata })
      achievements.index_with do |achievement|
        next AchievementRepositoryList.none unless achievement.user
        repos = achievement.user.top_acv_repositories(limit: REPO_LIMIT + 1)
        AchievementRepositoryList.new(repositories: repos)
      end
    end

    mobile_background_color "#0B2976"

    def link_text
      LINK_TEXT
    end

    def link_href
      LINK_HREF
    end

    def self.enabled?(_)
      true
    end

    def self.has_rounded_badge_variant?
      true
    end
  end
end
