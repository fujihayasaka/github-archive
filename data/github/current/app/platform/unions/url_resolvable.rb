# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class UrlResolvable < Platform::Unions::Base
      description "Types that may a URL may resolve to."

      visibility :internal, environments: [:dotcom]

      possible_types(
        Objects::Team,
        Objects::User,
        Objects::Bot,
        Objects::Repository,
        Objects::Organization,
        Objects::Issue,
        Objects::IssueComment,
        Objects::PullRequest,
        Objects::PullRequestReview,
        Objects::PullRequestReviewComment,
        Objects::Discussion,
        Objects::DiscussionComment,
        Objects::Release,
        Objects::UserAsset,
        Objects::RepositoryFile,
        Objects::Gist,
        Objects::App
      )
    end
  end
end
