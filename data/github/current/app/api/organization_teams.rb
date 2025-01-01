# typed: true
# frozen_string_literal: true

class Api::OrganizationTeams < Api::App
  include ReceiveSchemaWithOpenApi

  include Api::App::UsersDependency

  EXTERNAL_MANAGEMENT_RESTRICTION_ERROR = [
    "This team's membership is managed exclusively by %s. Learn more at",
    "#{GitHub.help_url}/articles/synchronizing-teams-between-your-identity-provider-and-github",
  ].join(" ")

  # list teams in :org
  get "/organizations/:organization_id/teams", operation_id: "teams/list" do
    control_access :list_teams,
      resource: org = find_org!,
      challenge: true,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    teams = if can_list_all_teams?
      org.teams
    else
      org.visible_teams_for(current_user).order(slug: :asc)
    end
    teams = paginate_rel(teams)

    GitHub::PrefillAssociations.prefill_batch_method(teams, :parent_team)

    deliver :team_hash, teams
  end

  # list the authenticated user's teams across all orgs
  get "/user/teams", operation_id: "teams/list-for-authenticated-user" do
    control_access :list_all_user_teams,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    scope = current_user.teams

    orgs = current_user.organizations
    if ProgrammaticActor::OrganizationFilter.applicable?(current_user)
      scope = Team.none # set the scope to `none` as a failsafe instead of a bunch of else's

      if orgs.any?
        accessible_org_ids = ProgrammaticActor::OrganizationFilter.perform(
          actor: current_user, organization_ids: orgs.pluck(:id), resource: "members"
        )

        orgs  = orgs.where(id: accessible_org_ids)
        scope = current_user.teams.owned_by(orgs)
      end
    elsif requestor_governed_by_oauth_application_policy?
      orgs = orgs.oauth_app_policy_met_by(current_app_via_oauth)
      scope = scope.owned_by(orgs)
    end

    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
    unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)

    set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
    scope = scope.excluding_organization_ids(unauthorized_org_ids) if unauthorized_org_ids.any?

    teams = paginate_rel(scope)

    GitHub::PrefillAssociations.prefill_associations(teams, { organization: :profile })
    GitHub::PrefillAssociations.prefill_associations(teams, :ldap_mapping) if GitHub.enterprise?
    GitHub::PrefillAssociations.prefill_batch_method(teams, :parent_team)

    deliver :team_hash, teams, full: true
  end

  CreateTeamQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($organization_id: ID!, $name: String!, $description: String, $privacy: TeamPrivacy!, $notification_setting: TeamNotificationSetting, $permission: LegacyTeamPermission, $repositories: [String], $maintainers: [String], $parentTeamId: ID, $ldap_dn: String, $includeFullTeamDetails: Boolean!) {
      createTeam(input: { organizationId: $organization_id, name: $name, description: $description, privacy: $privacy, notificationSetting: $notification_setting, permission: $permission, repositories: $repositories, maintainers: $maintainers, parentTeamId: $parentTeamId, ldap_dn: $ldap_dn })  {
        team {
          ...Api::Serializer::OrganizationsDependency::TeamFragment
        }
      }
    }
  GRAPHQL

  # create a team in :org
  post "/organizations/:organization_id/teams", operation_id: "teams/create" do
    control_access :create_team,
      resource: org = find_org!,
      challenge: true,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data  = receive_with_schema("team-full", "create-legacy")
    # DEPRECATED: :permission will be removed in API v4.
    attrs = attr(data, :name, :description, :permission, :notification_setting, :privacy, :ldap_dn, :parent_team_id)

    if attrs[:parent_team_id].present?
      parent_team = org.teams.find_by_id(attrs[:parent_team_id])
      has_get_team_access = access_allowed? :get_team,
        team: parent_team,
        organization: parent_team.try(:organization),
        resource: parent_team.try(:organization),
        allow_user_via_granular_actor: true,
        allow_integrations: true

      if parent_team.nil?
        set_forbidden_message "Invalid parent team id"
      elsif has_get_team_access
        set_forbidden_message "You must be a maintainer of the parent team"
      end

      control_access :admin_team,
        resource: parent_team.try(:organization),
        organization: parent_team.try(:organization),
        team: parent_team,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    end

    variables = {}
    variables[:includeFullTeamDetails] = true
    variables[:organization_id] = org.global_relay_id
    variables[:name] = attrs[:name]
    variables[:description] = attrs[:description] if attrs[:description]

    if attrs[:permission].present?
      if error_message = team_permission_error_message(attrs[:permission])
        deliver_error! 422, message: error_message, documentation_url: @documentation_url
      else
        variables[:permission] = attrs[:permission].upcase
      end
    end

    variables[:repositories] = data["repo_names"] if data["repo_names"]
    variables[:maintainers] = data["maintainers"] if data["maintainers"]
    variables[:parentTeamId] = parent_team.global_relay_id if parent_team
    variables[:ldap_dn] = attrs[:ldap_dn] if attrs[:ldap_dn] && GitHub.ldap_sync_enabled?

    variables[:privacy] =
      if Team.valid_privacy?(attrs[:privacy])
        Platform::Enums::TeamPrivacy.coerce_isolated_result(attrs[:privacy].to_s)
      elsif parent_team
        "VISIBLE"
      else
        "SECRET"
      end

    variables[:notification_setting] =
      if Team.valid_notification_setting?(attrs[:notification_setting])
        Platform::Enums::TeamNotificationSetting.coerce_isolated_result(attrs[:notification_setting].to_s)
      else
        "NOTIFICATIONS_ENABLED"
      end

    results = platform_execute(CreateTeamQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
        })
    else
      unless changeset_active?(:remove_team_permission)
        if attrs[:permission].present?
          GitHub.dogstats.increment("api.team_with_permission", { tags: ["permission:#{attrs[:permission]}", "action:create"] })
        end
      end

      case variables[:notification_setting]
      when Team::NOTIFICATIONS_ENABLED.upcase
        GitHub.dogstats.increment("api.team.notification_setting.count", tags: ["action:create", "setting:enabled"])
      when Team::NOTIFICATIONS_DISABLED.upcase
        GitHub.dogstats.increment("api.team.notification_setting.count", tags: ["action:create", "setting:disabled"])

        team = org.teams.find_by_name(variables[:name])

        if team.present?
          GlobalInstrumenter.instrument(
            "team.notification.setting",
            team_id: team.id,
            organization_id: team.organization.id,
            org_plan: team.organization.plan.name,
            business_id: team.organization.business&.id,
            business_type: team.organization.business&.business_type,
            notification_setting: Team::NOTIFICATIONS_DISABLED
          )
        end
      end

      deliver :graphql_team_hash, results.data.create_team.team, full: true, status: 201
    end
  end

  # get a team by id, by slug is automatically mapped
  get "/organizations/:organization_id/team/:team_id", operation_ids: ["teams/get-by-name", "teams/get-legacy"] do
    org = find_org!
    team = record_or_404(org.teams.find_by(id: int_id_param!(key: :team_id)))

    control_access :get_team,
      resource: team,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      organization: team.organization

    deliver :team_hash, team,
      full: true,
      last_modified: calc_last_modified_for_object(team)
  end

  UpdateTeamQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($id: ID!, $name: String, $description: String, $privacy: TeamPrivacy, $notification_setting: TeamNotificationSetting, $permission: LegacyTeamPermission, $parentTeamId: ID, $includeFullTeamDetails: Boolean!) {
      updateTeam(input: { teamId: $id, name: $name, description: $description, privacy: $privacy, notificationSetting: $notification_setting, permission: $permission, parentTeamId: $parentTeamId })  {
        team {
          ...Api::Serializer::OrganizationsDependency::TeamFragment
        }
      }
    }
  GRAPHQL

  # edit a team
  patch "/organizations/:org_id/team/:team_id", operation_ids: ["teams/update-in-org", "teams/update-legacy"] do
    team = find_team!
    original_notification_setting = team.notification_setting

    control_access :admin_team,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data  = receive_with_schema("team-full", "update-legacy")
    attrs = attr(data, :name, :description, :privacy, :notification_setting, :permission, :parent_team_id)

    if data&.has_key?("parent_team_id")
      if attrs[:parent_team_id].present?
        parent_team = team.organization.teams.find_by_id(attrs[:parent_team_id])
        has_get_team_access = access_allowed? :get_team,
          team: parent_team,
          organization: parent_team.try(:organization),
          resource: parent_team.try(:organization),
          allow_user_via_granular_actor: true,
          allow_integrations: true

        if has_get_team_access
          set_forbidden_message "You must be a maintainer of the parent team"
        end

        control_access :admin_team,
          resource: parent_team.try(:organization),
          organization: parent_team.try(:organization),
          team: parent_team,
          allow_integrations: true,
          allow_user_via_granular_actor: true
      end
    end

    variables = {
      id: team.global_relay_id,
    }

    variables[:name] = attrs[:name] if attrs[:name]
    variables[:includeFullTeamDetails] = true
    variables[:description] = attrs[:description] if attrs[:description]
    variables[:privacy] = Platform::Enums::TeamPrivacy.coerce_isolated_result(attrs[:privacy]) if Team.valid_privacy?(attrs[:privacy])
    variables[:notification_setting] = Platform::Enums::TeamNotificationSetting.coerce_isolated_result(attrs[:notification_setting]) if Team.valid_notification_setting?(attrs[:notification_setting])

    if attrs[:permission].present?
      if error_message = team_permission_error_message(attrs[:permission])
        deliver_error! 422, message: error_message, documentation_url: @documentation_url
      else
        variables[:permission] = attrs[:permission].upcase
      end
    end

    if attrs.has_key?(:parent_team_id)
      variables[:parentTeamId] = parent_team ? parent_team.global_relay_id : nil
    end

    results = platform_execute(UpdateTeamQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: "/rest/reference/teams#update-a-team",
        })
    else
      if attrs[:permission].present?
        log_data[:team_permission_changed_to] = attrs[:permission]
        GitHub.dogstats.increment("api.team_with_permission", { tags: ["permission:#{attrs[:permission].downcase}", "action:update"] })
      end

      # Tracks how many teams are updated to have notifications disabled (previously enabled) vs. notifications enabled (previously disabled).
      case variables[:notification_setting]
      when Team::NOTIFICATIONS_ENABLED.upcase
        if original_notification_setting != Team::NOTIFICATIONS_ENABLED
          GitHub.dogstats.increment("api.team.notification_setting.count", tags: ["action:update", "setting:enabled"])
        end
      when Team::NOTIFICATIONS_DISABLED.upcase
        if original_notification_setting != Team::NOTIFICATIONS_DISABLED
          GitHub.dogstats.increment("api.team.notification_setting.count", tags: ["action:update", "setting:disabled"])

          GlobalInstrumenter.instrument(
            "team.notification.setting",
            team_id: team.id,
            organization_id: team.organization.id,
            org_plan: team.organization.plan.name,
            business_id: team.organization.business&.id,
            business_type: team.organization.business&.business_type,
            notification_setting: Team::NOTIFICATIONS_DISABLED
          )
        end
      end

      deliver :graphql_team_hash, results.data.update_team.team, full: true
    end
  end

  DeleteTeamQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($id: ID!) {
      deleteTeam(input: { teamId: $id })  {
        isDestroyed
      }
    }
  GRAPHQL

  # delete a team
  delete "/organizations/:org_id/team/:team_id", operation_ids: ["teams/delete-in-org", "teams/delete-legacy"] do
    # Introducing strict validation of the team.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("team", "delete", skip_validation: true)

    team = find_team!
    control_access :admin_team,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      id: team.global_relay_id,
    }

    results = platform_execute(DeleteTeamQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
        })
    else
      deliver_empty(status: 204)
    end
  end

  ChildTeamsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($id: ID!, $limit: Int!, $numericPage: Int, $includeFullTeamDetails: Boolean!) {
      node(id: $id) {
        ... on Team {
          childTeams(first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::OrganizationsDependency::SimpleTeamFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  # get a list of child teams
  get "/organizations/:org_id/team/:team_id/teams", operation_ids: ["teams/list-child-in-org", "teams/list-child-legacy"] do
    team = find_team!

    control_access :get_team,
      resource: team,
      team: team,
      organization: team.organization,
      challenge: true,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      id: team.global_relay_id,
      includeFullTeamDetails: false,
      limit: per_page,
      numericPage: pagination[:page],
    }

    results = platform_execute(ChildTeamsQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
      })
    else
      child_teams = results.data.node.child_teams
      child_team_nodes = results.data.node.child_teams.edges.map(&:node)
      paginator.collection_size = child_teams.total_count
      deliver :graphql_team_hash, child_team_nodes
    end
  end

  # get permissions for an org team
  get "/organizations/:organization_id/team/:team_id/permissions", operation_id: "orgs/get-team-permissions" do
    team = find_team!(param_name: :team_id, org_param_name: :organization_id)
    org = team.organization

    enforce_plan_supports_custom_org_roles!(org)

    control_access :get_team,
      resource: team,
      team: team,
      organization: team.organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    teams = team.ancestors.to_a << team
    GitHub::PrefillAssociations.prefill_batch_method(teams, :org_roles)
    roles = teams.map { |team| team.org_roles }.flatten
    permissions = roles.uniq.map { |role| role.permissions.map(&:action) }.flatten.uniq

    deliver :org_team_permissions_hash, { permissions: permissions }
  end

  # Team Members
  #
  #

  # list team members
  get "/organizations/:org_id/team/:team_id/members", operation_ids: ["teams/list-members-in-org", "teams/list-members-legacy"] do
    team = find_team!
    control_access :get_team,
      resource: team,
      team: team,
      organization: team.organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role =
      case params[:role]
      when "maintainer" then "maintainer"
      when "member"     then "member"
      end

    users = ::Team::Membership::ScopeBuilder.new(
      team_id: team.id,
      viewer: current_user,
      membership: "all",
      role: role
    ).paged_scope(page: pagination[:page], per_page: per_page)

    deliver :simple_user_hash, users
  end

  # list team pending invitations
  get "/organizations/:org_id/team/:team_id/invitations", operation_ids: ["teams/list-pending-invitations-in-org", "teams/list-pending-invitations-legacy"] do
    deliver_error! 404 if GitHub.enterprise?

    team = find_team!
    set_forbidden_message "You must be an organization owner or team maintainer to list team invitations."
    control_access :list_team_invitations,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitations = team.pending_invitations.includes([:inviter, { invitee: [:profile] }]).order(:id)

    deliver :invitation_hash, paginate_rel(invitations)
  end

  # get if user is a team member (deprecated)
  get "/organizations/:org_id/team/:team_id/members/:username", operation_id: "teams/get-member-legacy" do
    team = find_team!
    control_access :get_team,
      team: team,
      organization: team.organization,
      resource: team.organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    user = this_user

    if team.member?(user)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # add user to a team (deprecated)
  put "/organizations/:org_id/team/:team_id/members/:username", operation_id: "teams/add-member-legacy" do
    @accepted_scopes = %w(admin:org repo)
    team = find_team!
    control_access :admin_team_membership,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_not_blocked! current_user, this_user

    user = this_user

    if !GitHub.bypass_org_invites_enabled? && org_invitation_sendable?(team.organization, user)
      error_code = :unaffiliated
    else
      res        = team.add_member(user, adder: current_user)
      error_code = res.status if res.error?
    end

    if error_code.present?
      error = translate_error(error_code, team.organization,
        @documentation_url)
      deliver_error(422, error)
    else
      deliver_empty(status: 204)
    end
  end

  # remove user from team (deprecated)
  delete "/organizations/:org_id/team/:team_id/members/:username", operation_id: "teams/remove-member-legacy" do
    @accepted_scopes = %w(admin:org repo)
    team = find_team!
    control_access :admin_team_membership,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    team.remove_member this_user

    deliver_empty(status: 204)
  end

  # Team Memberships
  #
  #

  # create, or update, a team membership
  put "/organizations/:org_id/team/:team_id/memberships/:username", operation_ids: ["teams/add-or-update-membership-for-user-in-org", "teams/add-or-update-membership-for-user-legacy"] do
    @accepted_scopes = %w(admin:org repo)
    success_status   = 200
    error_code       = nil
    team             = find_team!

    forbidden_message = if team&.external_group_team.present?
      "You cannot create or update members for an external group backed team since they are managed by #{team.external_group_team.external_group.display_name}"
    elsif team&.externally_managed?
      EXTERNAL_MANAGEMENT_RESTRICTION_ERROR % tenant_provider(team)
    elsif team&.enterprise_team_managed?
      "This team's membership is managed by an enterprise team."
    else
      "You must be an organization owner or team maintainer to add a team membership."
    end

    set_forbidden_message forbidden_message

    control_access :admin_team_membership,
      resource: team.organization,
      organization: team.organization,
      team: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_not_blocked! current_user, this_user

    # Introducing strict validation of the team-membership.replace
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("team-membership", "replace", skip_validation: true)
    team_role = data["role"] || "member"

    unless TeamInvitation.valid_role?(team_role)
      error = translate_error(:invalid_role, team.organization, @documentation_url)
      deliver_error!(422, error)
    end

    # This is kept for now as is to avoid a breaking change in the API. This should actually be
    # a HTTP status 451.
    if team.organization.has_full_trade_restrictions?
      error = translate_error(:restricted_org, team.organization, @documentation_url)
      deliver_error!(422, error)
    end

    # TODO: This needs to be revisited to directly add EMUs to the org / team if they are not org members
    if team.organization.direct_or_team_member?(this_user) || GitHub.bypass_org_invites_enabled?
      # The user is already affiliated with the org, or invites are disabled,
      # so we can add them to the team.

      # If invites are disabled, there may be an existing invitation for the user,
      # if so, go ahead and accept it.
      invitation = team.organization.pending_invitation_for(this_user)
      invitation.accept(acceptor: this_user) if invitation.present?

      # The user is already affiliated with the org, so we can add them to the
      # team.

      # Add the user to the team if they aren't already on it.
      unless team.member?(this_user)
        result     = team.add_member(this_user, adder: current_user)
        error_code = result.status if result.error?
      end

      # Add/remove the user's team maintainer status if requested.
      if error_code.nil?
        if team_role == "maintainer"
          begin
            team.promote_maintainer(this_user)
          rescue Team::Roles::MemberRequiredError
            error_code = :not_team_member
          rescue Organization::AbilityDependency::DirectMemberRequiredError
            error_code = :unaffiliated
          end
        elsif team_role == "member" && team.maintainer?(this_user)
          team.demote_maintainer(this_user)
        end
      end
    elsif !team.organization.has_seat_for?(this_user)
      # The user is not affiliated with the org yet,
      # doesn't have a pending invitation, and there are no seats available
      # for them, so we need the "no seat" error.
      error_code = Team::AddMemberStatus::NO_SEAT.status
    else
      # The user is not affiliated with the org yet, so we need to create or
      # update an invitation. Except EMUs.
      can_invite_to_org = !team.organization.business&.enterprise_managed_user_enabled?

      # Team Sync (group-syncer) cannot be allowed to send organization invites if the tenant is configured to forbid them
      if user_agent.group_syncer?

        # Team sync unavailable for GHES or EMUs
        if team.organization.business&.enterprise_managed_user_enabled?
          can_invite_to_org = false
        # Team sync is enabled at the enterprise level, differ to its tenant settings (enterprise is precedent)
        elsif team.organization.business&.team_sync_enabled?
          can_invite_to_org = !team.organization.business.team_sync_tenant.forbid_organization_invites
        # Team sync is enabled at the org level
        elsif team.organization.team_sync_tenant&.enabled?
          can_invite_to_org = !team.organization.team_sync_tenant.forbid_organization_invites
        # The group-syncer agent should not be invocating upon this endpoint if team sync is disabled
        else
          can_invite_to_org = false
        end
      end

      if can_invite_to_org
        begin
          invitation = team.organization.invite(this_user, inviter: current_user, teams: [team], invitation_source: :member)
          invitation.add_team(team, inviter: current_user, role: team_role)
        rescue OrganizationInvitation::InvalidError => e
          error_code = :invalid
          original_error_message = e.message
        rescue OrganizationInvitation::NoAvailableSeatsError => e
          # login used for logging therefore safe to use here.
          GitHub.logger.error({
            exception: e,
            "code.namespace": "Api::OrganizationTeams",
            "gh.org.login": team.organization.login, # rubocop:disable GitHub/DoNotAllowLogin
            "gh.team.slug": team.slug,
            "gh.thisuser.login": this_user.login, # rubocop:disable GitHub/DoNotAllowLogin
            "gh.enduser.login": current_user.login, # rubocop:disable GitHub/DoNotAllowLogin
            "gh.thisuser.team_role": team_role,
            "gh.org.at_seat_limit": team.organization.at_seat_limit?,
            "gh.thisuser.pending_invitation": team.organization.pending_invitation_for(this_user).present?,
            "gh.data": data
          })
          error_code = Team::AddMemberStatus::NO_SEAT.status
        rescue ActiveRecord::RecordInvalid => e
          # We're getting duplicate team errors on race conditions when
          # someone submits two identical requests simultaneously. We 201 in
          # this case to indicate that the resource has already been created.
          #
          # For more context, see:
          # - https://github.com/github/github/issues/39606
          # - https://github.com/github/github/pull/39674
          if e.record && e.record.errors[:team_id].present?
            success_status = 201
          else
            error_code = :invalid
            original_error_message = e.message
          end
        end
      # Organization invite is not allowed for the current scenario
      else
        # If the code flow has gotten to this section, they're an EMU not yet part of the organization.
        # For now we will require them to be part of the organization to be invited to a team.
        # https://github.com/github/Identity-Teams/issues/898
        if team.organization.business&.enterprise_managed_user_enabled?
          error_code = :emu_not_org_member
        else
          error_code = Team::AddMemberStatus::NO_PERMISSION.status
        end

        # login used for logging therefore safe to use here.
        if user_agent.group_syncer?
          GitHub.logger.info(
            "group-syncer agent attempted to invite user to organization, and blocked",
            "gh.user": this_user.login, # rubocop:disable GitHub/DoNotAllowLogin
            "gh.business": team.organization.business&.slug,
            "gh.organization": team.organization.login, # rubocop:disable GitHub/DoNotAllowLogin
            "http.user_agent": user_agent.to_s,
          )
          GitHub.dogstats.increment("api.teams.membership", tags: ["user_agent:group_syncer", "forbid_organization_invites:true"])
        end
      end
    end

    if error_code.present?
      error = translate_error(error_code, team.organization, @documentation_url, original_error_message)
      deliver_error(422, error)
    else
      if user_agent.group_syncer?
        GitHub.dogstats.increment("api.teams.membership", tags: ["user_agent:group_syncer", "forbid_organization_invites:false"])
      end
      deliver :team_membership_hash, { team: team, user: this_user }, status: success_status
    end
  end

  # get a team membership
  get "/organizations/:org_id/team/:team_id/memberships/:username", operation_ids: ["teams/get-membership-for-user-in-org", "teams/get-membership-for-user-legacy"] do
    team = find_team!
    user = this_user

    control_access :get_team_membership,
      resource: team,
      team: team,
      member: user,
      organization: team.organization,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if team.membership_state_of(user, immediate_only: false) == :inactive
      deliver_error 404
    else
      deliver :team_membership_hash, { team: team, user: user }
    end
  end

  delete "/organizations/:org_id/team/:team_id/memberships/:username", operation_ids: ["teams/remove-membership-for-user-in-org", "teams/remove-membership-for-user-legacy"] do
    # Introducing strict validation of the team-membership.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("team-membership", "delete", skip_validation: true)

    team = find_team!
    user = this_user

    forbidden_message = if team&.external_group_team.present?
      "You cannot remove members for an external group backed team since they are managed by #{team.external_group_team.external_group.display_name}"
    elsif team&.enterprise_team_managed?
      "This team's membership is managed by an enterprise team."
    elsif team&.externally_managed?
      EXTERNAL_MANAGEMENT_RESTRICTION_ERROR % tenant_provider(team)
    elsif user == current_user
      "You need at least admin:org scope to remove yourself from this team."
    else
      "You must be an organization owner or team maintainer to remove a team membership."
    end

    set_forbidden_message forbidden_message
    control_access :delete_team_membership,
      resource: team.organization,
      team: team,
      organization: team.organization,
      member: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if team.member?(user)
      team.remove_member(user)
    elsif invitation = team.pending_invitation_for(user)
      invitation.remove_team(team)
    end

    deliver_empty(status: 204)
  end

  private

  # Finds the Team defined in the URL request and
  # sets the current_org if found.
  #
  # Returns a Team instance.
  def find_team(param_name: :team_id, org_param_name: :org_id)
    @team ||= Team.find_by(id: int_id_param!(key: param_name), organization_id: int_id_param!(key: org_param_name))
    @current_org ||= @team.try(:organization)
    @team
  end

  def org_invitation_sendable?(org, user)
    !org.at_seat_limit? && logged_in? && !org.direct_or_team_member?(user)
  end

  # Private: Translate a Team::AddMemberStatus error code to an API 422 response.
  #
  # error_code        - A Symbol error code.
  # org               - An Organization.
  # documentation_url - String url for documentation.
  #
  # Returns a Hash.
  def translate_error(error_code, org, documentation_url, original_error_message = nil)
    response = {
      message: "Validation Failed",
      errors: [{ code: error_code, field: :user, resource: :TeamMember, message: original_error_message }],
      documentation_url: documentation_url,
    }

    case error_code
    when :blocked
      response[:message] = "User is blocked. #{GitHub.support_link_text}."
    when :dupe
      response[:message] = "User is already a member."
    when :org
      response[:message] = "Cannot add an organization as a member."
    when :no_seat
      response[:message] = "You must purchase at least one more seat to add this user as a member."
      response[:documentation_url] = "https://github.com/organizations/#{org.display_login}/settings/billing/seats"
    when :pending_cycle_no_seat
      response[:message] = "You must cancel your pending seat downgrade."
      response[:documentation_url] = "https://github.com/organizations/#{org.display_login}/settings/billing"
    when :no_2fa
      response[:message] = "User doesn't satisfy the two-factor authentication requirements for this organization."
    when :unaffiliated
      response[:message] = "User isn't a member of this organization. Please invite them first."
    when :not_team_member
      response[:message] = "User isn't a member of this team. Please add them to the team first."
      response[:documentation_url] = "/rest/reference/teams#add-or-update-team-membership-for-a-user"
    when :already_org_admin
      response[:message] = "User is already an admin of this organization, so they can't be promoted to a team maintainer."
    when :invalid_role
      response[:message] = "You specified an invalid team member role."
    when :restricted_org
      response[:message] = ::TradeControls::Notices.notice_as_plaintext(:organization_account_restricted)
      response[:documentation_url] = GitHub.trade_controls_help_url
    when :emu_not_org_member
      response[:message] = "Enterprise Managed Users must be part of the organization to be assigned to the team."
    end

    response
  end

  def can_list_all_teams?
    enabled = GitHub.enterprise_only_api_enabled?
    enabled && access_allowed?(:list_all_teams, allow_integrations: false, allow_user_via_granular_actor: false)
  end

  def can_list_all_repos?
    enabled = GitHub.enterprise_only_api_enabled?
    enabled && access_allowed?(:list_all_team_repos, allow_integrations: false, allow_user_via_granular_actor: false)
  end

  def tenant_provider(team)
    team.organization.team_sync_tenant.provider_label
  end

  def team_permission_error_message(permission)
    if changeset_active?(:remove_team_permission)
      "Setting team permission is no longer supported"
    elsif permission.downcase == "admin"
      "Setting team permission to admin is no longer supported"
    else
      nil
    end
  end

  def enforce_plan_supports_custom_org_roles!(org)
    deliver_error! 422, message: "Feature not available for the #{org.login_for_api} organization." unless org.custom_roles_supported?
  end
end
