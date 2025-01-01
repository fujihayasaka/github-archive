# typed: true
# frozen_string_literal: true

class Api::OrganizationDependabotAlerts < Api::App
  include Api::App::DependabotAlertsHelpers

  # List Dependabot alerts for an organization
  get "/organizations/:organization_id/dependabot/alerts", operation_id: "dependabot/list-alerts-for-org" do
    org = find_org!

    control_access :list_org_dependabot_alerts,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_non_conflicting_cursor_params!

    # If this is a request where the actor has programmatic granular
    # permissions (i.e: PAT v2, or GitHub Apps), filter the repositories before we send the request.
    programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(org)

    # If the request is made with a programmatic actor (i.e: PAT v2, or GitHub Apps) and the actor cannot access all
    # repos in the org, we find only the repos that the actor can access.
    # When the request is made with an OAuth app or a legacy PAT, and `security_events` is not part of the scope, we find only public repos of the org.
    # Otherwise, we set `repository_ids` to `nil`, which means that the actor can access all repos in the org.
    repository_ids = if programmatic_actor_grant
      unless programmatic_actor_grant.installed_on_all_repositories?
        programmatic_actor_grant.repository_ids(min_action: :read, resource: "vulnerability_alerts")
      end
    elsif !scope?(current_user, "security_events")
      org.repositories.public_scope.pluck(:id)
    end

    # Bail out early if the programmatic actors don't have access to
    # any of the repositories in question. This check is mostly for
    # extra safety. It seems to be hard to run into this case normally.
    if programmatic_actor_grant && repository_ids.is_a?(Array) && repository_ids.empty?
      deliver_error! 404
    end

    alerts = alerts_for_organization(organization: org, allowed_repository_ids: repository_ids, cursor_pagination: using_cursor_based_pagination?)

    deliver :dependabot_alerts_hash, { alerts: alerts }, include_repository: true, last_modified: calc_last_modified(alerts)
  rescue Platform::Errors::Cursor,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
