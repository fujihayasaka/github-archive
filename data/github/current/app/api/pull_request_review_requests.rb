# typed: true
# frozen_string_literal: true

class Api::PullRequestReviewRequests < Api::App
  include ReceiveSchemaWithOpenApi

  RequestReviewersMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: RequestReviewsInput!) {
      requestReviews(input: $input) {
        pullRequest {
          number
        }
      }
    }
  GRAPHQL

  # create a review request on a pull request
  post "/repositories/:repository_id/pulls/:pull_number/requested_reviewers", operation_id: "pulls/request-reviewers" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)

    control_access :request_pull_request_review,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("pull-request-review-request", "create-legacy")

    users_to_add = User.where(login: data["reviewers"])
    allowed_reviewer_ids = pull.available_review_user_ids(filter: users_to_add)

    # allow the Copilot code review bot at this stage
    # CCR access checks will filter the bot out later, if needed
    ccr_bot_id = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id
    if ccr_bot_id.present?
      allowed_reviewer_ids << ccr_bot_id
    end

    disallowed = (users_to_add.map(&:id) - allowed_reviewer_ids).any?

    teams_to_add = []
    if data["team_reviewers"]
      teams_to_add = repo.teams(immediate_only: false, include_all_repo_roles: true).where(slug: data["team_reviewers"])

      # tried to add a team that doesn't exist for this repository.
      if data["team_reviewers"].length != teams_to_add.length
        deliver_error! 422, message: "Reviews may only be requested from collaborators. One or more of the teams you specified is not a collaborator of the #{repo.name_with_owner_for_api} repository."
      end
    end
    allowed_teams = pull.available_review_teams(filter: teams_to_add)
    disallowed_teams = (teams_to_add - allowed_teams).any?

    if users_to_add.include?(pull.user)
      deliver_error! 422, message: "Review cannot be requested from pull request author."
    elsif disallowed || disallowed_teams
      deliver_error! 422, message: "Reviews may only be requested from collaborators. One or more of the users or teams you specified is not a collaborator of the #{repo.name_with_owner_for_api} repository."
    end

    reviewer_global_ids = users_to_add.map(&:global_relay_id)
    team_global_ids = teams_to_add.map(&:global_relay_id)

    input_variables = {
      "input" => {
        "pullRequestId" => pull.global_relay_id,
        "userIds" => reviewer_global_ids,
        "teamIds" => team_global_ids,
        "union" => true,
      },
    }
    results = platform_execute(RequestReviewersMutation, variables: input_variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    pull.reload
    PullRequest.prefill_associations([pull])
    deliver :pull_request_hash, pull, status: 201
  end

  # remove a review request from a pull request
  delete "/repositories/:repository_id/pulls/:pull_number/requested_reviewers", operation_id: "pulls/remove-requested-reviewers" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    control_access :update_pull_request,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    data = receive_with_schema("pull-request-review-request", "delete-legacy")

    reviewers = pull.review_requests.pending.users.to_a
    downcased_reviewers_to_remove = data["reviewers"].map(&:downcase)
    reviewers.reject! { |user| downcased_reviewers_to_remove.include?(user.login_for_api.downcase) }
    reviewer_global_ids = reviewers.map(&:global_relay_id)

    teams = pull.review_requests.pending.teams.to_a
    teams.reject! { |team| data["team_reviewers"]&.include?(team.slug) }
    team_global_ids = teams.map(&:global_relay_id)

    input_variables = {
      "input" => {
        "pullRequestId" => pull.global_relay_id,
        "userIds" => reviewer_global_ids,
        "teamIds" => team_global_ids,
      },
    }
    results = platform_execute(RequestReviewersMutation, variables: input_variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    pull.reload
    PullRequest.prefill_associations([pull])
    deliver :pull_request_hash, pull
  end

  # get a list of review request including users and teams for a pull request
  get "/repositories/:repository_id/pulls/:pull_number/requested_reviewers", operation_id: "pulls/list-requested-reviewers" do
    repo = find_repo!
    pull = record_or_404 PullRequest.with_number_and_repo(params[:pull_number], repo)
    control_access :list_pull_request_review_requests,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :requested_reviewers_hash, pull
  end
end
