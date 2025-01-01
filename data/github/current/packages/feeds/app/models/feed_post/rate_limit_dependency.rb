# typed: false
# frozen_string_literal: true

module FeedPost::RateLimitDependency
  def user_for_rate_limited_creation
    author
  end
end
