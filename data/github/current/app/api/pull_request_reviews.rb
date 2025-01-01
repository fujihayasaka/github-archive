# typed: true
# frozen_string_literal: true

class Api::PullRequestReviews < Api::App
  include ReceiveSchemaWithOpenApi

  CreatePullRequestReviewQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($pullRequestId: ID!, $body: String, $commitOID: GitObjectID, $event: PullRequestReviewEvent, $comments: [DraftPullRequestReviewComment], $threads: [DraftPullRequestReviewThread], $clientMutationId: String!) {
      addPullRequestReview(input: {
        pullRequestId: $pullRequestId,
        commitOID: $commitOID,
        body: $body,
        event: $event,
        comments: $comments,
        threads: $threads,
        clientMutationId: $clientMutationId
      }) {
        review: pullRequestReview {
          ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
        }
      }
    }
  GRAPHQL

  # Create a new review
  post "/repositories/:repository_id/pulls/:pull_number/reviews", operation_id: "pulls/create-review" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    control_access :create_pull_request_comment,
      repo: repo,
      resource: pull,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("pull-request-review", "create-legacy")

    input_variables = {
      "pullRequestId"    => pull.global_relay_id,
      "commitOID"        => data["commit_id"],
      "body"             => data["body"],
      "event"            => data["event"],
      "clientMutationId" => request_id,
    }

    uses_positioning = repo.feature_enabled?(:pull_requests_rest_serialize_new_positioning) && repo.feature_enabled?(:graphql_pr_comment_positioning)

    if data["threads"]
      data["threads"].each do |comment|
        comment.transform_keys! { |k| k.camelize(:lower) }
      end
      input_variables["threads"] = data["threads"]
    end

    if data["comments"]
      data["comments"].each do |comment|
        comment.transform_keys! { |k| k.camelize(:lower) }
      end

      # Grab multiline and single line comments
      multiline, single = *data["comments"].partition { |c| c.keys.include? "line" }

      if multiline&.any?
        input_variables["threads"] = [input_variables["threads"], multiline].compact.flatten
      end

      if single&.any?
        input_variables["comments"] = single
      end
    end

    if repo.feature_enabled?(:pull_requests_rest_serialize_new_positioning)
      (input_variables["threads"] || []).each do |thread|
        if uses_positioning && positioning = thread.delete("positioning")
          positioning.transform_keys! { |k| k.camelize(:lower) }

          case positioning.delete("type")
          when "FILE"
            thread["filePositioning"] = positioning
          when "LINE"
            thread["linePositioning"] = positioning
          when "MULTILINE"
            thread["multilinePositioning"] = positioning
          end
        end
      end
    end

    results = platform_execute(CreatePullRequestReviewQuery, variables: input_variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error!(results, inputs: input_variables, resource: "PullRequestReview")
    end

    deliver :graphql_pull_request_review_hash, results.data.add_pull_request_review.review
  end

  DeletePullRequestReviewQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($pullRequestReviewId: ID!, $clientMutationId: String!) {
      deletePullRequestReview(input: {
        pullRequestReviewId: $pullRequestReviewId,
        clientMutationId: $clientMutationId
      }) {
        review: pullRequestReview {
          ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
        }
      }
    }
  GRAPHQL

  # Delete a review
  delete "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id", operation_id: "pulls/delete-pending-review" do
    receive_with_schema("pull-request-review", "delete")

    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    review = record_or_404 pull.reviews.find_by_id(params[:review_id])
    control_access :delete_pull_request_review,
      repo: repo,
      resource: review,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    input_variables = {
      "pullRequestReviewId" => review.global_relay_id,
      "clientMutationId"    => request_id,
    }
    results = platform_execute(DeletePullRequestReviewQuery, variables: input_variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error!(results, inputs: input_variables, resource: "PullRequestReview")
    end

    deliver :graphql_pull_request_review_hash, results.data.delete_pull_request_review.review
  end

  UpdatePullRequestReviewQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($pullRequestReviewId: ID!, $body: String!, $clientMutationId: String!) {
      updatePullRequestReview(input: {
        pullRequestReviewId: $pullRequestReviewId,
        body: $body,
        clientMutationId: $clientMutationId
      }) {
        review: pullRequestReview {
          ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
        }
      }
    }
  GRAPHQL

  # Update a review
  put "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id", operation_id: "pulls/update-review" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    review = record_or_404 pull.reviews.find_by_id(params[:review_id])

    control_access :update_pull_request_comment,
      repo: repo,
      resource: pull,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("pull-request-review", "update")

    input_variables = {
      "pullRequestReviewId" => review.global_relay_id,
      "body"                => data["body"],
      "clientMutationId"    => request_id,
    }

    results = platform_execute(UpdatePullRequestReviewQuery, variables: input_variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error!(results, inputs: input_variables, resource: "PullRequestReview")
    end

    deliver :graphql_pull_request_review_hash, results.data.update_pull_request_review.review
  end

  IndexPullRequestReviewQuery = PlatformClient.parse <<-'GRAPHQL'
    query($pullRequestId: ID!, $limit: Int!, $numericPage: Int) {
      node(id: $pullRequestId) {
        ... on PullRequest {
          reviews(first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              review: node {
                ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  # All reviews for a pull request
  get "/repositories/:repository_id/pulls/:pull_number/reviews", operation_id: "pulls/list-reviews" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    control_access :list_pull_request_comments,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      "pullRequestId" => pull.global_relay_id,
      "limit" => pagination[:per_page] || DEFAULT_PER_PAGE,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(IndexPullRequestReviewQuery, variables: variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error!(results, inputs: variables, resource: "PullRequestReview")
    end

    pr_reviews = results.data.node.reviews
    paginator.collection_size = pr_reviews.total_count
    deliver :graphql_pull_request_review_hash, pr_reviews.edges.map { |edge| edge.review }
  end

  ShowPullRequestReviewQuery = PlatformClient.parse <<-'GRAPHQL'
    query($pullRequestReviewId: ID!) {
      review: node(id: $pullRequestReviewId) {
        ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
      }
    }
  GRAPHQL

  # Get a specific review
  get "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id", operation_id: "pulls/get-review" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    review = record_or_404 pull.reviews.find_by_id(params[:review_id])
    control_access :list_pull_request_comments,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      "pullRequestReviewId" => review.global_relay_id,
    }

    results = platform_execute(ShowPullRequestReviewQuery, variables: variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error!(results, inputs: variables, resource: "PullRequestReview")
    end

    deliver :graphql_pull_request_review_hash, results.data.review
  end

  IndexPullRequestReviewCommentsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($pullRequestReviewId: ID!, $limit: Int!, $numericPage: Int) {
      review: node(id: $pullRequestReviewId) {
        ... on PullRequestReview {
          comments(first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              comment: node {
                ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewCommentFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  # Get a specific reviews comments
  get "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/comments", operation_id: "pulls/list-comments-for-review" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    review = record_or_404 pull.reviews.find_by_id(params[:review_id])
    control_access :list_pull_request_comments,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      "pullRequestReviewId" => review.global_relay_id,
      "limit" => pagination[:per_page] || DEFAULT_PER_PAGE,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(IndexPullRequestReviewCommentsQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    pr_review_comments = results.data.review.comments
    paginator.collection_size = pr_review_comments.total_count
    deliver :graphql_pull_request_review_comment_hash, pr_review_comments.edges.map { |edge| edge.comment }
  end
end
