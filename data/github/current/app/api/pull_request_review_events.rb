# typed: true
# frozen_string_literal: true

class Api::PullRequestReviewEvents < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::DatabaseResourceUpdateRateLimiting

  SubmitPullRequestReviewMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($pullRequestReviewId: ID!, $clientMutationId: String!, $event: PullRequestReviewEvent!, $body: String) {
      submitPullRequestReview(input: {
        pullRequestReviewId: $pullRequestReviewId,
        clientMutationId: $clientMutationId,
        event: $event,
        body: $body
      }) {
        review: pullRequestReview {
          ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
        }
      }
    }
  GRAPHQL

  # Submit an event for a PullRequestReview
  post "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/events", operation_id: "pulls/submit-review" do
    repo = find_repo!
    pull = record_or_404(PullRequest.with_number_and_repo(params[:pull_number], repo))
    review = record_or_404(pull.reviews.find_by_id(params[:review_id]))
    control_access :submit_pull_request_review,
      repo: repo,
      resource: review,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("pull-request-review", "submit-legacy")
    variables = {
      "pullRequestReviewId" => review.global_relay_id,
      "clientMutationId" => request_id,
      "event" => data["event"],
      "body" => data["body"],
    }

    results = platform_execute(SubmitPullRequestReviewMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_pull_request_review_hash, results.data.submit_pull_request_review.review
  end

  DismissPullRequestReviewMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($pullRequestReviewId: ID!, $clientMutationId: String!, $message: String!) {
      dismissPullRequestReview(input: {
        pullRequestReviewId: $pullRequestReviewId,
        clientMutationId: $clientMutationId,
        message: $message
      }) {
        review: pullRequestReview {
          ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
        }
      }
    }
  GRAPHQL

  put "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/dismissals", operation_id: "pulls/dismiss-review" do
    repo = find_repo!
    pull = record_or_404(PullRequest.with_number_and_repo(params[:pull_number], repo))
    review = record_or_404(pull.reviews.find_by_id(params[:review_id]))
    control_access :dismiss_pull_request_review,
      repo: repo,
      resource: review,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if pull.base_branch_rule_evaluator&.restricted_dismissed_reviews? &&
      !pull.base_branch_rule_evaluator.review_dismissable_by?(current_user)

      deliver_error!(403, message: "Branch protections do not permit dismissing this review")
    end

    check_database_resource_update_rate_limit!(resource: review, repo: repo, current_user: current_user)

    data = receive_with_schema("pull-request-review", "dismiss-legacy")
    variables = {
      "pullRequestReviewId" => review.global_relay_id,
      "clientMutationId" => request_id,
      "message" => data["message"],
    }

    results = platform_execute(DismissPullRequestReviewMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_pull_request_review_hash, results.data.dismiss_pull_request_review.review
  end
end
