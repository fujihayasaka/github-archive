# typed: true
# frozen_string_literal: true

#
# NOTE: The data set here is written with every audit log event. Please ping
# the @github/audit-log team if adding/removing/updating any fields.
#

module Api::App::AuditDependency
  extend T::Helpers
  requires_ancestor { Api::App }
  requires_ancestor { Api::App::FindersDependency }

  def initialize_audit_context
    # WARNING: Do not call any methods that can cause the request to
    # short-circuit  (e.g., don't call any methods that attempt to authenticate
    # the request). Doing so will prevent us from fully populating the context.
    context = {
      actor_ip: remote_ip,
      user_agent: request.user_agent.to_s,
      controller: self.class.to_s,
      from: "%s#%s" % [self.class, request.request_method],
      request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
      request_method: request.env["REQUEST_METHOD"].downcase,
      request_category: request_category,
      server_id: Rack::ServerId.get(request.env),
      version: medias.to_api_semantic_version,
      is_robot: robot?,
    }

    unless request.query_string.empty?
      context[:query_string] = query_string_for_logging
    end

    Audit.context.push(context)
  end

  def find_api_request_target
    business = T.let(nil, T.untyped)
    org = T.let(nil, T.untyped)
    repo = T.let(nil, T.untyped)

    ActiveRecord::Base.connected_to(role: :reading) do
      repo = find_repo
      if repo && (repo.private? || repo.internal?) && repo.has_business_owner?
        org = repo.owner if repo.in_organization?
        business = repo.business_owner
      else
        repo = nil
      end

      if org.nil?
        org = find_org
        if org
          business = org.business
        end
      end

      if business.nil?
        business = find_enterprise
      end
    end

    {
      business: business,
      org: org,
      repo: repo,
    }
  end

  PullIDRegex = %r{/repositories/\d+/pulls/(?<pull_id>\d+)(/|$)}

  def find_api_request_pr(repo)
    unless repo.nil?
      if match = PullIDRegex.match(request.path)
        ActiveRecord::Base.connected_to(role: :reading) do
          repo.issues.find_by_number(match[:pull_id]).try(:pull_request)
        end
      end
    end
  end


  # these are controllers that do repo stuff that are security relevant
  API_CONTROLLERS = Set[
    :AppTestTestApp, # controller used in test only
    :Repositories,
    :RepositoryActionsPermissions,
    :RepositoryBranches,
    :RepositoryCollaborators,
    :RepositoryCommits,
    :RepositoryContents,
    :RepositoryInvitations,
    :RepositoryRules,
  ]

  # these are controllers that do even more stuff that is security relevant
  EXTENDED_API_CONTROLLERS = API_CONTROLLERS | Set[
    :ActionsSecrets,
    :ActionsVariables,
    :AuditLogEnterprise,
    :AuditLogOrganization,
    :Billing,
    :CheckRuns,
    :CheckSuites,
    :CodespacesSecretsOrganization,
    :CodespacesSecretsRepository,
    :DeploymentBranchPolicies,
    :DeploymentProtectionRules,
    :EnterpriseActionsPermissions,
    :EnterpriseGroupsScim,
    :EnterpriseInstallation,
    :EnterpriseSecretScanning,
    :EnterpriseUsersScim,
    :Git,
    :GitBlobs,
    :GitCommits,
    :GitRefs,
    :GitTags,
    :GitTrees,
    :IntegrationInstallations,
    :Integrations,
    :Legacy,
    :OrganizationActionsPermissions,
    :OrganizationActionsSecrets,
    :OrganizationActionsVariables,
    :OrganizationCustomOrgRoles,
    :OrganizationCustomRoles,
    :OrganizationDependabotSecrets,
    :OrganizationExternalGroups,
    :OrganizationFineGrainedOrgPermissions,
    :OrganizationHooks,
    :OrganizationInvitations,
    :OrganizationOutsideCollaborators,
    :OrganizationProgrammaticAccessGrantRequests,
    :OrganizationProgrammaticAccessGrants,
    :OrganizationRoleAssignment,
    :Organizations,
    :OrganizationsCredentialAuthorizations,
    :OrganizationSecurityManagers,
    :OrganizationsScim,
    :OrganizationTeamRepositories,
    :OrganizationTeams,
    :OrganizationTeamSync,
    :Pulls,
    :RequiredWorkflows
  ]

  def instrument_api_request
    # when an api request come in
    return if internal_ip_request? || GitHub.enterprise?

    # get the api requests controller
    controller = self.class.to_s.delete_prefix("Api::").gsub("::", "").to_sym

    # get all the relevant requested data
    target = find_api_request_target

    business = target[:business]
    org = target[:org]
    pr = target[:pr]
    repo = target[:repo]

    # return unless the business has enabled request events streaming
    return unless business && business.api_request_events_enabled?
    # return unless the business has enabled all events or the controller is considered security relevant
    return unless business.feature_enabled?(:audit_log_all_api_events) || EXTENDED_API_CONTROLLERS.include?(controller)

    request.body.rewind
    request_body = request.body.read
    event = {
      application_name: current_app&.name,
      business: business,
      integration: current_integration&.name,
      org: org,
      query_string: request.query_string,
      rate_limit_remaining: @rate&.remaining,
      repo: repo,
      request_body: request_body.truncate_bytes(1_000_000, omission: ""),
      request_method: request.request_method,
      route: route_pattern,
      status_code: response.status,
      url_path: request.path,
      user: current_user,
    }

    if repo && controller == :Pulls
      # include relevant PR info if available and this request was handled by the Pulls controller
      pr = find_api_request_pr(repo)
      if pr
        event.merge!({
          pull_request_id: pr.id,
          pull_request_url: pr.permalink,
        })
      end
    end

    # emit audit log event that will be streamed to subscribed business customers
    GitHub.instrument "api.request", event
  end

  def update_audit_log_rate_limit_amount
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
    return unless GitHub.flipper[:audit_log_api_rate_limit].enabled?
    return unless GitHub.flipper[:audit_log_api_rate_limit_cost].enabled?
    return if GitHub.flipper[:audit_log_rate_limit_exempt].enabled?(current_user)

    query_cost = response.headers["X-AuditLog-Query-Cost"] || 1
    update_rate_limit_amount(query_cost.to_i)
  end
end
