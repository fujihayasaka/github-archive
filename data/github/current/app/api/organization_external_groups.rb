# typed: true
# frozen_string_literal: true

class Api::OrganizationExternalGroups < Api::App
  FORBIDDEN_MESSAGE = "You must be an organization owner to view IdP managed groups."
  ENTERPRISE_NOT_ENABLED_ERROR = "This organization is not part of externally managed enterprise."
  TEAM_CANNOT_BE_EXTERNALLY_MANAGED = "This team cannot be externally managed since it has explicit members."

  private def get_external_groups_control(org)
    # This returns all groups in memory
    get_external_groups(org).map { |group| Api::Serializer.serialize(:external_group_hash, group) }
  end

  private def get_external_groups_paginate_rel_fast(org)
    relation = org.business
                 .external_provider
                 .external_groups
                 .not_deleted
                 .display_name_filter(params[:display_name])

    paginate_rel_fast_page(relation, order_by: :display_name)
  end

  # Public: Get list of available groups
  #
  # Returns an array json representation of an external groups defined in external-group.json
  get "/organizations/:organization_id/external-groups", operation_id: "teams/list-external-idp-groups-for-org" do
    set_forbidden_message FORBIDDEN_MESSAGE

    control_access :admin_team,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 400, message: ENTERPRISE_NOT_ENABLED_ERROR unless enterprise_enabled?(org)

    groups = get_external_groups_paginate_rel_fast(org)

    deliver(
      :external_group_hash,
      { groups: groups },
      { nested_pagination_key: :groups, current_user: current_user },
    )
  end

  # Public: Get more information about an external group including teams and members.
  #     Teams will be scoped to the context of an organization.
  #
  # Note: Our API only supports "page" and "per_page" parameters for pagination.
  # The response contains two arrays - members and teams. It is more likely that
  # there are many more members than there are teams. Therefore, we only support
  # pagination on the members array because we don't have query parameters to
  # specify pagination for each array individually. The "per_page" and "page"
  # parameters are used for the members pagination only.
  #
  # Returns a json representation of an external group defined in external-group.json
  get "/organizations/:organization_id/external-group/:group_id", operation_id: "teams/external-idp-group-info-for-org" do
    set_forbidden_message FORBIDDEN_MESSAGE

    control_access :admin_team,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 400, message: ENTERPRISE_NOT_ENABLED_ERROR unless enterprise_enabled?(org)

    group = get_external_groups(org, id: params[:group_id])
    deliver_error! 404 unless group

    team_ids = org.teams.pluck(:id)
    group = Api::Serializer.serialize(:external_group_hash, group, team_ids: team_ids, full_group_info: true)

    # Paginate the members array
    members = group[:members]
    paginated_members = members.sort_by { |member| member[:member_name] }.paginate(pagination)

    # Set pagination headers based on the members' pagination
    set_pagination_headers(collection_size: members.count)

    response = group.merge(members: paginated_members)
    deliver_raw(response, status: 200)
  end

  # Public: Returns a list of external groups that are associated with a team
  #
  # Returns a json representation of an external group defined in external-group.json
  get "/organizations/:org_id/team/:team_id/external-groups", operation_id: "teams/list-linked-external-idp-groups-to-team-for-org" do
    team = find_team!
    org = team.organization

    set_forbidden_message FORBIDDEN_MESSAGE

    control_access :admin_team,
      resource: org,
      organization: org,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 400, message: ENTERPRISE_NOT_ENABLED_ERROR unless enterprise_enabled?(org)
    deliver_error! 400, message: TEAM_CANNOT_BE_EXTERNALLY_MANAGED if team.explicit_members?

    external_group_teams = ExternalGroupTeam.where(team_id: team.id)

    group = external_group_teams.first&.external_group if external_group_teams.any?

    groups = if group
      [Api::Serializer.serialize(:external_group_hash, group)]
    else
      []
    end

    deliver_raw({ groups: groups }, status: 200)
  end

  # Public: Links a team to an external group, if a team has already been linked it will re-link it to a passed in group
  #
  # Returns a json representation of an external group defined in external-group.json
  patch "/organizations/:org_id/team/:team_id/external-groups", operation_id: "teams/link-external-idp-group-to-team-for-org" do
    team = find_team!
    org = team.organization

    set_forbidden_message FORBIDDEN_MESSAGE

    control_access :admin_team,
      resource: org,
      organization: org,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 400, message: ENTERPRISE_NOT_ENABLED_ERROR unless enterprise_enabled?(org)
    deliver_error! 400, message: TEAM_CANNOT_BE_EXTERNALLY_MANAGED if team.explicit_members?

    json = receive_with_schema("external-group", "link-external-group")

    group = get_external_groups(org, id: json["group_id"])
    deliver_error! 404 unless group

    reconcile_external_group(team, group.id)

    team_ids = org.teams.pluck(:id)
    group = Api::Serializer.serialize(:external_group_hash, group, team_ids: team_ids, full_group_info: true)
    deliver_raw(group, status: 200)
  end

  # Public: Unlinks the external group from a team.  Operation on a team that is not linked produces a no-op.
  #
  # Returns No content
  delete "/organizations/:org_id/team/:team_id/external-groups", operation_id: "teams/unlink-external-idp-group-from-team-for-org" do
    team = find_team!
    org = team.organization

    set_forbidden_message FORBIDDEN_MESSAGE

    control_access :admin_team,
      resource: org,
      organization: org,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 400, message: ENTERPRISE_NOT_ENABLED_ERROR unless enterprise_enabled?(org)

    deliver_empty(status: 204) unless team.external_group_team.present?

    receive_with_schema("external-group", "unlink-external-group", skip_validation: true)

    reconcile_external_group(team, nil)

    deliver_empty(status: 204)
  end

  private

  # Private: Check if an organization is enabled for this API.  It has to be either EMU,
  # or GHES with SCIM.  SAML has to be already enabled on a business.
  #
  # Returns Boolean
  def enterprise_enabled?(org)
    return true if GitHub.single_business_environment? && org.business&.enterprise_server_scim_enabled?
    org.business&.enterprise_managed_user_and_external_provider_enabled?
  end

  # Private: Finds an external group based on an id and the provider attached to an organization's business
  #
  # Returns ExternalGroup array or single when id present
  def get_external_groups(organization, id: nil)
    groups = organization.business.external_provider
      .external_groups
      .not_deleted

    return groups.find_by_id(id) if id.present?

    # Check is the query was passed in and add a scope to filter on a display_name
    if params[:display_name].present?
      groups = groups.like_display_name(params[:display_name])
    end

    groups
  end

  # Private: Method to reconcile added/deleted groups when team is updated
  #
  # Returns nothing
  def reconcile_external_group(team, group_id)
    # Delete external group team
    if group_id.nil? && team.external_group_team.present?
      team.external_group_team.destroy

    # update external group
    elsif group_id && team.external_group_team.present?
      return if team.external_group_team.external_group_id == group_id

      team.external_group_team.external_group_id = group_id
      team.external_group_team.save

    # create external group
    elsif group_id
      ExternalGroupTeam.create(external_group_id: group_id, team_id: team.id)
    end
  end
end
