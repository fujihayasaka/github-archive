# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class UnlockingModel < Platform::Unions::Base
      description "Types that may be associated with an unlocking event of an AchievementTier."
      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::AchievementRepositoryList,
        Objects::CommitComment,
        Objects::Discussion,
        Objects::DiscussionComment,
        Objects::TeamDiscussion,
        Objects::TeamDiscussionComment,
        Objects::Issue,
        Objects::IssueComment,
        Objects::PullRequest,
        Objects::PullRequestReview,
        Objects::PullRequestReviewComment,
        Objects::Release,
        Objects::Repository,
        Objects::RepositoryAdvisory,
        Objects::RepositoryAdvisoryComment,
        Objects::Sponsorship,
      )
    end
  end
end
