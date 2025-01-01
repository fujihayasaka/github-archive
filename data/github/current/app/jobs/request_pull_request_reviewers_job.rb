# typed: true
# frozen_string_literal: true

class RequestPullRequestReviewersJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests,
                ApplicationRecord::Collab,
                ApplicationRecord::Mysql2

  use_replicas ApplicationRecord::Mysql1,
               ApplicationRecord::Mysql5,
               ApplicationRecord::Notify,
               ApplicationRecord::Repositories,
               ApplicationRecord::IamAbilities,
               ApplicationRecord::Configurations,
               ApplicationRecord::Spokes,
               allow_replication_lag: [
                ApplicationRecord::Iam
               ]

  queue_as :request_pr_reviewers

  retry_on PullRequest::DetermineCodeownersError, attempts: 1
  retry_on_recoverable_exceptions

  def perform(pull_request, user, should_re_request_reviews: true)
    pull_request.request_review_from_codeowners(user, should_save: true)

    pull_request.review_requests.deferred.each do |request|
      request.ready!(user: user)
    end
  end
end
