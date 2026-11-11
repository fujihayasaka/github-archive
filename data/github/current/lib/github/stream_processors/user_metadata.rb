# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      autoload :UserMetadataBaseProcessor, "github/stream_processors/user_metadata/user_metadata_base_processor"

      autoload :AchievementProcessor, "github/stream_processors/user_metadata/achievement_processor"
      autoload :DeveloperProgramMembershipProcessor, "github/stream_processors/user_metadata/developer_program_membership_processor"
      autoload :DiscussionAnswerProcessor, "github/stream_processors/user_metadata/discussion_answer_processor"
      autoload :GlobalAdvisoryCreditProcessor, "github/stream_processors/user_metadata/global_advisory_credit_processor"
      autoload :PackageProcessor, "github/stream_processors/user_metadata/package_processor"
      autoload :ProBadgeProcessor, "github/stream_processors/user_metadata/pro_badge_processor"
      autoload :ProjectProcessor, "github/stream_processors/user_metadata/project_processor"
      autoload :RepoProcessor, "github/stream_processors/user_metadata/repo_processor"
      autoload :SponsorProcessor, "github/stream_processors/user_metadata/sponsor_processor"
      autoload :StarProcessor, "github/stream_processors/user_metadata/star_processor"
      autoload :UserFollowProcessor, "github/stream_processors/user_metadata/user_follow_processor"
      autoload :UserTeamMembershipProcessor, "github/stream_processors/user_metadata/user_team_membership_processor"

      autoload :Events, "github/stream_processors/user_metadata/events"
    end
  end
end
