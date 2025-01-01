# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module CommunityInsights
      autoload :DiscussionPageViewProcessor, "github/stream_processors/community_insights/discussion_page_view_processor"
      autoload :ContributionActivityProcessor, "github/stream_processors/community_insights/contribution_activity_processor"
    end
  end
end
