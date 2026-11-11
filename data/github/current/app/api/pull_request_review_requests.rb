# typed: true
# frozen_string_literal: true

class Api::PullRequestReviewRequests < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::DatabaseResourceUpdateRateLimiting

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

    check_database_resource_update_rate_limit!(resource: pull, repo: repo, current_user: current_user)

    data = receive_with_schema("pull-request-review-request", "create-legacy")

    bots_to_add, users_to_add = User.where(login: data["reviewers"]).partition { |user| user.is_a? Bot }
    allowed_reviewer_ids = pull.available_review_user_ids(filter: users_to_add)

    # allow the Copilot code review bot at this stage
    # CCR access checks will filter the bot out later, if needed
    ccr_bot_id = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id
    if ccr_bot_id.present?
      allowed_reviewer_ids << ccr_bot_id
    end

    disallowed = (users_to_add.map(&:id) - allowed_reviewer_ids).any?

    # Handle team review request assignment
    teams_to_add = []
    if data["team_reviewers"]
      if repo.organization&.business_team_pr_reviewers_enabled?
        # Feature enabled: support both org and business teams using domain method
        data["team_reviewers"].each do |slug|
          normalized_slug = slug.delete_prefix("/")
          team = Orgs.domain.teams.find_team_with_organization_context(
            repo.organization,
            team_slug: normalized_slug
          )
          teams_to_add << team if team
        end

        if data["team_reviewers"].length != teams_to_add.length
          deliver_error! 422, message: "Reviews may only be requested from collaborators. One or more of the teams you specified is not a collaborator of the #{repo.name_with_owner_for_api} repository."
        end
      else
        # Feature disabled: legacy behavior - org teams only, silently ignore business team slugs
        org_team_slugs = data["team_reviewers"].reject { |slug| BusinessTeam.business_team_slug?(slug.delete_prefix("/")) }
        teams_to_add = repo.teams(immediate_only: false, include_all_repo_roles: true).where(slug: org_team_slugs)

        if org_team_slugs.length != teams_to_add.length
          deliver_error! 422, message: "Reviews may only be requested from collaborators. One or more of the teams you specified is not a collaborator of the #{repo.name_with_owner_for_api} repository."
        end
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
    bot_global_ids = bots_to_add.map(&:global_relay_id)
    team_global_ids = teams_to_add.map(&:global_relay_id)

    input_variables = {
      "input" => {
        "pullRequestId" => pull.global_relay_id,
        "userIds" => reviewer_global_ids,
        "botIds" => bot_global_ids,
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

    # When flag enabled, use type_teams(org) to include business teams in the set.
    # When disabled, use legacy .teams scope (business teams can't be preserved
    # through the mutation regardless, due to filter_allowed_reviewers).
    teams = if repo.organization&.business_team_pr_reviewers_enabled?
      pull.review_requests.pending.type_teams(repo.organization).map(&:reviewer).to_a
    else
      pull.review_requests.pending.teams.to_a
    end
    if data["team_reviewers"]
      normalized_slugs = data["team_reviewers"].map { |slug| slug.delete_prefix("/") }
      teams.reject! { |team| normalized_slugs.include?(team.slug) }
    end
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
