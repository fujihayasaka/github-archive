# typed: true
# frozen_string_literal: true

class Api::OrganizationInvitations < Api::App
  include ReceiveSchemaWithOpenApi
  include GitHub::RateLimitable

  get "/organizations/:organization_id/invitations", operation_id: "orgs/list-pending-invitations" do
    deliver_error! 404 if GitHub.bypass_org_invites_enabled?

    org = find_org!

    deliver_error! 404 if org&.enterprise_managed_user_enabled?

    set_forbidden_message "You must be an admin to view organization pending invitations."
    control_access :read_org_invitations,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitations = org.pending_invitations.includes([:inviter, { invitee: [:profile] }])

    invitations = invitations.with_invitation_source(invitation_source) if invitation_source.present?
    invitations = invitations.order(:id).limit(OrganizationInvitation::PENDING_INVITATIONS_QUERY_LIMIT)

    reinstate_user_ids = invitations
      .filter_map { |org_invite| org_invite.invitee.id if org_invite.invitee.present? && org_invite.role == "reinstate" }
    restorable_admin_ids = Restorable::OrganizationUser.restorable_memberships(org, reinstate_user_ids)
      .select { |membership| membership.subject_type == "Organization" }
      .group_by(&:user_id)
      .map { |_, memberships| memberships.max_by(&:id) }
      .filter_map { |membership| membership.user_id if membership.action == Ability::ACTION_RANKING[:admin] }

    invitations = invitations.map do |org_invite|
      if org_invite.role == "reinstate"
        if org_invite.invitee.present? && restorable_admin_ids.include?(org_invite.invitee.id)
          org_invite.role = "admin"
        else
          org_invite.role = "direct_member"
        end
      end

      if org_invite.invitation_source == "unknown" && org_invite.external_identity.present?
        org_invite.invitation_source = "scim"
      end

      next nil if org_invite.invitee.present? && org_invite.invitee.is_enterprise_managed?

      org_invite
    end.compact

    invitations = invitations.select { |org_invite| org_invite.role == role.to_s } if role.present?

    deliver :invitation_hash, paginate_rel(invitations)
  end

  get "/organizations/:organization_id/failed_invitations", operation_id: "orgs/list-failed-invitations" do
    deliver_error! 404 if GitHub.bypass_org_invites_enabled?

    org = find_org!

    deliver_error! 404 if org&.enterprise_managed_user_enabled?

    set_forbidden_message "You must be an admin to view organization failed invitations."
    control_access :read_org_invitations,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitations = org.failed_invitations.where(cancelled_at: nil).includes(
      [:inviter, { invitee: [:profile] }]).order(:id)

    deliver :invitation_hash, paginate_rel(invitations)
  end

  # Create a new org invitation
  post "/organizations/:organization_id/invitations", operation_id: "orgs/create-invitation" do
    deliver_error! 404 if GitHub.bypass_org_invites_enabled?

    set_forbidden_message "You must be an admin to create an invitation to an organization."

    org = find_org!

    deliver_error! 404 if org&.enterprise_managed_user_enabled?

    control_access :create_organization_invitation,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    attributes = attr(receive_with_schema("organization-invitation", "create-legacy"), :email, :invitee_id, :role, :team_ids)

    if invitee_id = attributes[:invitee_id]
      invitee = User.find_by(id: invitee_id)
      unless invitee.present?
        deliver_error! 422, message: "Invalid invitee_id", documentation_url: @documentation_url
      end

      if invitee.is_enterprise_managed?
        deliver_error! 422,
          errors: [{
            resource: "OrganizationInvitation",
            code: :unprocessable,
            field: "data",
            message: "Invitee cannot be invited to this organization",
          }],
          documentation_url: @documentation_url
      end

      if attributes[:role] == "reinstate"
        restorable_memberships = Restorable::OrganizationUser.restorable_memberships(org, invitee.id)
        deliver_error! 422, message: "No previous privileges to reinstate", documentation_url: @documentation_url if restorable_memberships.none?
      end
    end

    teams = org.teams.where(id: attributes[:team_ids])
    if teams.any?(&:enterprise_team_managed?)

      deliver_error! 422,
        errors: [{
          resource: "OrganizationInvitation",
          code: :unprocessable,
          field: "team_ids",
          message: "You cannot invite users to organization teams managed by an enterprise team"
        }],
        documentation_url: @documentation_url
    end

    role = attributes[:role] || "direct_member"
    unless %w[direct_member admin billing_manager reinstate].include?(role)
      deliver_error! 422,
        errors: [{
          resource: "OrganizationInvitation",
          code: :unprocessable,
          field: "role",
          message: "Variable $role of type OrganizationInvitationRole was provided invalid value"
        }],
        documentation_url: @documentation_url
    end

    # Must obey rate limits
    limit_policy = OrganizationInvitation::RateLimitPolicy.new(org)
    limit_key = "orgs/invitations.new:org-#{org.id}"
    if rate_limit_increment(limit_key, { max_tries: limit_policy.limit, ttl: limit_policy.ttl }).at_limit?
      deliver_error! 422,
        errors: [{
          resource: "OrganizationInvitation",
          code: :unprocessable,
          field: "data",
          message: "Over invitation rate limit"
        }],
        documentation_url: @documentation_url
    end

    begin
      invitation = org.invite(invitee, inviter: current_user, role: role.to_sym, email: attributes[:email], teams: teams, invitation_source: :member)
      deliver :invitation_hash, invitation, status: 201
    rescue OrganizationInvitation::InvalidError, OrganizationInvitation::NoAvailableSeatsError, ActiveRecord::RecordInvalid, OrganizationInvitation::TradeControlsError => error
      deliver_error! 422,
        errors: [{
          resource: "OrganizationInvitation",
          code: :unprocessable,
          field: "data",
          message: error.to_s,
        }],
        documentation_url: @documentation_url
    end
  end

  # Cancel an org invitation
  delete "/organizations/:organization_id/invitations/:invitation_id", operation_id: "orgs/cancel-invitation" do
    deliver_error! 404 if GitHub.bypass_org_invites_enabled?
    receive_with_schema("organization-invitation", "cancel")

    set_forbidden_message "You must be an admin to cancel an invitation to an organization."
    org = find_org!

    deliver_error! 404 if org&.enterprise_managed_user_enabled?

    control_access :cancel_organization_invitation,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitation = record_or_404(
      OrganizationInvitation.find_by(organization_id: org.id, id: params[:invitation_id])
    )

    begin
      invitation.cancel(actor: current_user)
    rescue OrganizationInvitation::AlreadyAcceptedError
      deliver_error! 422,
        message: "You cannot cancel an accepted invitation.",
        documentation_url: @documentation_url
    end

    deliver_empty status: 204
  end

  OrganizationInvitationTeamsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($invitationId: ID!, $pageSize: Int!, $page: Int, $includeFullTeamDetails: Boolean!, $skipImmediateRepositories: Boolean!) {
      node(id: $invitationId) {
        ... on OrganizationInvitation {
          teams(first: $pageSize, numericPage: $page) {
            totalCount
            nodes {
              ...Api::Serializer::OrganizationsDependency::SimpleTeamFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # list teams on an org invitation
  get "/organizations/:organization_id/invitations/:invitation_id/teams", operation_id: "orgs/list-invitation-teams" do
    deliver_error! 404 if GitHub.bypass_org_invites_enabled?

    set_forbidden_message "You must be an admin to list the teams off an organization invitation."

    org = find_org!

    deliver_error! 404 if org&.enterprise_managed_user_enabled?

    invitation = record_or_404(org.pending_invitations.find_by_id(params[:invitation_id]))

    control_access :list_organization_invitation_teams,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    results = platform_execute(OrganizationInvitationTeamsQuery, variables: {
      includeFullTeamDetails: false,
      skipImmediateRepositories: false,
      invitationId: invitation.global_relay_id,
      pageSize: pagination[:per_page],
      page: pagination[:page],
    })

    set_pagination_headers(collection_size: results.data.node.teams.total_count)

    deliver :graphql_team_hash, results.data.node.teams.nodes
  end

  private

  def role
    case params[:role]
    when "admin"
      :admin
    when "direct_member"
      :direct_member
    when "billing_manager"
      :billing_manager
    when "hiring_manager"
      :hiring_manager
    end
  end

  def invitation_source
    case params[:invitation_source]
    when "scim"
      :scim
    when "member"
      :member
    end
  end
end
