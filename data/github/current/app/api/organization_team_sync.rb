# typed: true
# frozen_string_literal: true

class Api::OrganizationTeamSync < Api::App
  TEAM_SYNC_NOT_ENABLED_ERROR = [
    "This team is not externally managed. Learn more at",
    "#{GitHub.help_url}/articles/synchronizing-teams-between-your-identity-provider-and-github",
  ].join(" ")

  INVALID_PAGE_TOKEN_MESSAGE = "Unable to execute query; invalid page token specified."

  # Get list of available groups
  get "/organizations/:organization_id/team-sync/groups", operation_id: "teams/list-idp-groups-for-org" do
    set_forbidden_message "You must be an organization owner or team maintainer to view team sync status."

    control_access :manage_org_users,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_error! 403, message: TEAM_SYNC_NOT_ENABLED_ERROR unless endpoint_available?(org)
    deliver_error! 404 unless public_api_enabled?(org)

    response = GroupSyncer.client.list_groups(org_id: org.global_relay_id,
                                              query: params[:q].presence,
                                              page_size: params[:per_page].to_i,
                                              page_token: params[:page].to_s,
                                             )

    if response.error
      deliver_error! 429, message: "API call exceeded rate limit due to too many requests" if response.error.meta["status_code"] == "429"

      deliver_error! 401, message: "Invalid token provided." if response.error.meta["status_code"] == "401"

      if response.error.meta["status"] == "400"
        # This isn't my favorite way to decide to catch the 400, but we don't want to catch 400s that really should
        # be reported to us as 500s that we just haven't seen yet since Group Syncer is our proxy.
        formatted_body = response.error.meta["body"].gsub("=>", ":") rescue "{}"
        error_details = JSON.parse(formatted_body) rescue nil
        if error_details && error_details["error"] && error_details["error"]["message"].include?(INVALID_PAGE_TOKEN_MESSAGE)
          deliver_error! 400, message: INVALID_PAGE_TOKEN_MESSAGE
        end
      end

      err = ::TeamSync::ServiceResponseError.new("[#{response.error.code}] #{response.error.msg}: #{response.error.meta}")
      Failbot.report!(
        err,
        org_id: org.id,
        query: params[:q].presence,
        page_size: params[:per_page].to_i,
        page_token: params[:page].to_s,
      )

      deliver_error! 500, message: "An error occurred while fetching group data, please try again"
    end

    response_groups = response.data.groups
    groups = response_groups.map { |group| Api::Serializer.serialize(:group_hash, group) }

    @links.add_current({ page: response.data.next_page_token }, rel: "next") if response.data.next_page_token.present?
    deliver_raw({ groups: groups }, status: 200)
  end

  get "/organizations/:org_id/team/:team_id/team-sync/group-mappings", operation_ids: ["teams/list-idp-groups-in-org", "teams/list-idp-groups-for-legacy"] do
    team = find_team!
    @current_org = team.organization
    set_forbidden_message "You must be an organization owner or team maintainer to view team sync status."

    control_access :manage_team_sync_mappings,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_error! 403, message: TEAM_SYNC_NOT_ENABLED_ERROR unless endpoint_available?(team)
    deliver_error! 404 unless public_api_enabled?(team.organization)

    mappings = team.group_mappings.map { |mapping| Api::Serializer.serialize(:mapping_hash, mapping) }

    deliver_raw({ groups: mappings }, status: 200)
  end

  # Add remove mappings

  patch "/organizations/:org_id/team/:team_id/team-sync/group-mappings", operation_ids: ["teams/create-or-update-idp-group-connections-in-org", "teams/create-or-update-idp-group-connections-legacy"] do
    team = find_team!
    @current_org = team.organization
    set_forbidden_message "You must be an organization owner or team maintainer to modify group mappings for this team."

    control_access :manage_team_sync_mappings,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_error! 403, message: TEAM_SYNC_NOT_ENABLED_ERROR unless endpoint_available?(team)

    groups_param = receive_with_schema("group-mapping", "update-group-mappings")["groups"]

    deliver_error! 422 unless groups_param

    groups = groups_param.map(&:symbolize_keys)

    Team::GroupMapping.batch_update_mappings(team, groups, actor: current_user)

    current_mappings = team.group_mappings.map { |mapping| Api::Serializer.serialize(:mapping_hash, mapping) }

    deliver_raw({ groups: current_mappings }, status: 200)
  end

  patch "/organizations/:org_id/team/:team_id/team-sync/group-mappings-state", operation_id: :internal do
    @route_owner = "@github/team-sync"
    team = find_team!

    control_access :update_group_mappings_state,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    deliver_error! 403, message: TEAM_SYNC_NOT_ENABLED_ERROR unless endpoint_available?(team)

    input = receive_with_schema("group-mapping", "group-mappings-state")
    team.group_mappings.update_all(synced_at: input["synced_at"], status: input["status"])

    deliver_empty(status: 204)
  end

  private

  def endpoint_available?(item)
    case item
    when Team
      item.can_be_externally_managed?
    when Organization
      item.team_sync_enabled?
    end
  end

  def public_api_enabled?(org)
    team_sync_provider = TeamSync::Provider.detect(issuer: org.external_identity_session_owner.saml_provider.issuer)
    team_sync_provider.azuread? || team_sync_provider.okta?
  end
end
