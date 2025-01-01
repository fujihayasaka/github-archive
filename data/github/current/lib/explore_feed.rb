# typed: true
# frozen_string_literal: true

module ExploreFeed
  autoload :CustomerStory, "explore_feed/customer_story"
  autoload :Event, "explore_feed/event"
  autoload :PopularDeveloper, "explore_feed/popular_developer"
  autoload :ProfessionalService, "explore_feed/professional_service"
  autoload :Recommendation, "explore_feed/recommendation"
  autoload :RepositoryGoodFirstIssue, "explore_feed/repository_good_first_issue"
  autoload :Spotlight, "explore_feed/spotlight"
  autoload :Trending, "explore_feed/trending"

  autoload :ExploreFeedError, "explore_feed/explore_feed_error"
  autoload :ValidationHelpers, "explore_feed/validation_helpers"
end
