# typed: true
# frozen_string_literal: true

class Api::OrganizationTeamRepositories < Api::App
  include ReceiveSchemaWithOpenApi
  include GitHub::RateLimitable

  MAX_DELETE_CALLS_PER_TTL = 100
  MAX_UPDATE_CALLS_PER_TTL = 100
  TTL = 1.minute

  # list repos in a team
  #
  # Note that this logic is essentially duplicated from the Repos Connection on
  # the Team GraphQL object. The reason it's duplicated here is that the
  # previous GraphQL implemenation was found to be significantly slower than
  # this implementation, causing timeouts.
  #
  # Related: https://github.com/github/github/pull/138931
  get "/organizations/:org_id/team/:team_id/repos", operation_ids: ["teams/list-repos-in-org", "teams/list-repos-legacy"] do
    team = find_team!
    control_access :list_team_repos,
      resource: team,
      team: team,
      organization: team.try(:organization),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    scope = team.sorted_visible_repositories_for(
        current_user,
        affiliation: :all,
        sort: { field: "name", direction: "ASC" }
      )
      .where(owner_id: @current_org.id)
      .filter_spam_and_disabled_for(current_user)

    if current_app
      scope = ::Repository.oauth_app_policy_approved_repository_scope(
        repository_scope: scope,
        app: current_app,
      )
    end

    scope = scope.includes(:network, :owner, :repository_license, :repository_licenses, :organization, :page, :mirror)
      .paginate(
        page: pagination[:page],
        per_page: per_page
      )

    # Add prefill_associations so that issue count on repositories are batched
    # The batch happens in https://github.com/github/github/blob/bcb9f9112a662945058121c12855d89250c8f106/packages/issues/app/models/repository/issue_dependency.rb#L134-L135
    # When adding the call to prefill_associations
    Repository.prefill_associations(scope)

    deliver :team_repo_hash, scope, team: team
  end

  # get if a repo is in a team
  get "/organizations/:org_id/team/:team_id/repositories/:repository_id", operation_ids: ["teams/check-permissions-for-repo-in-org", "teams/check-permissions-for-repo-legacy"] do
    team = find_team!
    repo = find_repo

    control_access :get_team_repo,
      team: team,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if team.direct_or_inherited_repo_ids(affiliation: :all).include?(repo.id)
      if medias.api_param?(:repository)
        Repository.prefill_associations([repo], internal: true)

        deliver :team_repo_hash,
            repo,
            team: team,
            generate_temp_clone_token: access_allowed?(
              :get_temp_clone_token,
              resource: repo,
              current_repo: repo,
              allow_integrations: true,
              allow_user_via_granular_actor: false
            ),
            show_merge_settings: access_allowed?(
              :push,
              resource: repo,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            ),
            status: 200
      else
        deliver_empty(status: 204)
      end
    else
      deliver_error 404
    end
  end

  UpdateTeamRepositoryQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($teamId: ID!, $repositoryId: ID!, $permission: String!) {
      updateTeamRepository(input: { teamId: $teamId, repositoryId: $repositoryId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  # add a repo to a team
  put "/organizations/:org_id/team/:team_id/repositories/:repository_id", operation_ids: ["teams/add-or-update-repo-permissions-in-org", "teams/add-or-update-repo-permissions-legacy"] do
    team = find_team!
    repo = find_repo!

    if enforce_rate_limit?
      limit_key = "orgs/teams.update:org-#{@current_org.id}"
      if rate_limit_increment(limit_key, { max_tries: MAX_UPDATE_CALLS_PER_TTL, ttl: TTL }).at_limit?
        deliver_error! 429,
          message: "Rate Limit Exceeded",
          errors: [api_error(:OrganizationTeamRepositories, :repository, :unprocessable)]
      end
    end

    has_get_team_repo_access = access_allowed? :get_team_repo,
      team: team,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if has_get_team_repo_access
      set_forbidden_message "You must have administrative rights on this repository."
    end

    control_access :add_team_repo,
      team: team,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Introducing strict validation of the team-repository.replace
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("team-repository", "replace", skip_validation: true)

    if data.has_key?("permission")
      permission = data["permission"]
    else
      # In legacy org membership, teams had a team-wide permission that applied
      # to every repository on the team. In the API, we fall back to that
      # team-wide permission if none is specified, so that old API clients
      # operating on old teams will continue to function normally.
      GitHub.dogstats.increment "team.legacy_team_permission_default"
      permission = team.permission
    end

    # Preserve the behavior of returning a 422 for invalid roles but return a
    # 403 if the passed role can not be assigned due to the organizations
    # billing plan
    permission, code = team.fetch_permission(permission)

    unless Role.valid_system_role?(permission)
      GitHub.dogstats.increment "team.add_repo_permission.custom_role"
    end

    case code
    when :forbidden
      return deliver_error(403)
    when :not_found
      return deliver_error(422)
    when :success
      permission = permission&.to_s
    end

    # For business teams, use direct model method instead of GraphQL mutation
    # since business teams may not be properly resolvable in GraphQL schema
    if team.is_a?(BusinessTeam)
      result = team.update_repository_permission(repo, permission)
      case result
      when Team::ModifyRepositoryStatus::SUCCESS
        deliver_empty(status: 204)
      when Team::ModifyRepositoryStatus::NOT_OWNED
        deliver_error(403, message: "Repository must be owned by the business.")
      when Team::ModifyRepositoryStatus::NO_PERMISSION
        deliver_error(422, message: "Invalid permission specified.")
      when Team::ModifyRepositoryStatus::DUPE
        deliver_empty(status: 204) # Already exists, treat as success
      else
        deliver_error(422, message: "Could not update team repository permission.")
      end
    else
      # Use GraphQL mutation for regular teams
      results = platform_execute(UpdateTeamRepositoryQuery, variables: {
        teamId: team.global_relay_id,
        repositoryId: repo.global_relay_id,
        permission: permission,
      })

      if results.errors.all.any?
        deprecated_deliver_graphql_error({
          errors: results.errors.all,
          resource: "TeamRepository",
          documentation_url: @documentation_url,
        })
      else
        deliver_empty(status: 204)
      end
    end
  end

  # remove a repo from a team
  delete "/organizations/:org_id/team/:team_id/repositories/:repository_id", operation_ids: ["teams/remove-repo-in-org", "teams/remove-repo-legacy"] do

    # Introducing strict validation of the team-repository.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("team-repository", "delete", skip_validation: true)

    @documentation_url = "/rest/reference/teams#remove-a-repository-from-a-team"
    @accepted_scopes = %w(admin:org repo)

    team = find_team!
    repo = find_repo!

    if enforce_rate_limit?
      limit_key = "orgs/teams.delete:org-#{@current_org.id}"
      if rate_limit_increment(limit_key, { max_tries: MAX_DELETE_CALLS_PER_TTL, ttl: TTL }).at_limit?
        deliver_error! 429,
          message: "Rate Limit Exceeded",
          errors: [api_error(:OrganizationTeamRepositories, :repository, :unprocessable)]
      end
    end

    has_get_team_repo_access = access_allowed? :get_team_repo,
      team: team,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if has_get_team_repo_access
      set_forbidden_message "You must have administrative rights on a repository or team in order to remove the repository from that team"
    end

    control_access :remove_team_repo, team: team, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true

    if repo.access_group_setting&.includes_team?(team.id)
      return deliver_error 403,
        message: "You cannot remove repositories managed by group settings.",
        documentation_url: "#{GitHub.help_url}/organizations".freeze
    end

    team.remove_repository repo

    deliver_empty(status: 204)
  end

  private

  # Finds the Team defined in the URL request and
  # sets the current_org if found.
  #
  # Returns a Team instance.
  def find_team(param_name: :team_id, org_param_name: :org_id, with_business_teams: false)
    # If the team was found and cached in the router, use that to save
    # lookups.
    found_team = env[GitHub::Routers::Api::ThisTeamKey] || super(param_name:, org_param_name:, with_business_teams: true)

    if found_team.is_a?(BusinessTeam)
      business = found_team.business

      # Unset the found_team if the feature flag does not permit returning the BusinessTeam.
      if business.nil? || !business.erp_feature_enabled?(:enterprise_teams_org_roles)
        found_team = nil
      end
    end

    @current_org = found_team.try(:organization)

    found_team
  end

  # Private: Check if rate limits are enabled for this request.
  #
  # Returns a boolean
  def enforce_rate_limit?
    return false if GitHub.single_business_environment?
    return false unless @current_org

    true
  end
end
