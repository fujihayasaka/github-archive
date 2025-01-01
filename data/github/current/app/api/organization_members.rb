# typed: true
# frozen_string_literal: true

class Api::OrganizationMembers < Api::App
  include ReceiveSchemaWithOpenApi

  include Api::App::UsersDependency

  # list members of :org
  get "/organizations/:organization_id/members", operation_id: "orgs/list-members" do
    org = find_org!

    control_access :apps_audited,
      resource: Platform::PublicResource.new(resource: org),
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false # we aren't enforcing it here because the filters underneath are.

    can_audit_two_factor = logged_in? && \
      meets_oauth_application_policy_for_this_org? && \
      access_allowed?(:list_two_factor_disabled_members,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )

    if wants_two_factor_audit? && !can_audit_two_factor
      deliver_error! 422,
        message: "Only owners can use this filter.",
        documentation_url: "/v3/orgs/members/#audit-two-factor-auth"
    end

    if access_allowed?(:list_private_org_members,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
      )
      user_ids = org.visible_user_ids_for(current_user, type: type_of_users_to_fetch)
    else
      user_ids = org.public_member_ids.take(Organization::MEGA_ORG_MEMBER_THRESHOLD)
    end

    users = if user_ids.empty?
      User.none
    else
      User.where(id: user_ids)
    end

    users = users.two_factor_disabled if filters.include?("2fa_disabled")
    if filters.include?("2fa_insecure") && org.feature_flag_enabled?(:org_members_2fa_level, default: false)
      users = users.with_insecure_two_factor_methods
    end

    if medias.api_param?("user-identity")
      users = users.includes(:profile)
    end

    users = paginate_rel(users.order("users.login"))

    deliver :user_hash, users
  end

  # list public members of :org
  get "/organizations/:organization_id/public_members", operation_id: "orgs/list-public-members" do
    org = find_org!
    @accepted_scopes = []
    control_access :list_public_members,
                   resource: org,
                   allow_integrations: true,
                   allow_user_via_granular_actor: true,
                   enforce_oauth_app_policy: false

    users = org.visible_users_for(current_user, actor_ids: org.public_member_ids)

    # login used for sorting therefore safe to use here.
    users = users.order(login: :asc).paginate(pagination) # rubocop:disable GitHub/DoNotAllowLogin
    deliver :user_hash, users
  end

  # get if a user is a member of :org
  get "/organizations/:organization_id/members/:username", operation_id: "orgs/check-membership-for-user" do
    org, user = find_org!, this_user

    @accepted_scopes = %w(read:org repo user)
    control_access :list_public_members,
                   resource: org,
                   enforce_oauth_app_policy: false,
                   allow_integrations: true,
                   allow_user_via_granular_actor: true

    redirect(public_members_url) unless can_view_private_members?

    # requesters w/o private membership visibility are redirected to
    # equivalent public membership urls

    if user && org.visible_user_ids_for(current_user, actor_ids: user.id).any?
      deliver_empty(status: 204)
    else
      deliver_error 404,
        message: "User does not exist or is not a member of the organization",
        documentation_url: @documentation_url
    end
  end

  # get permissions for an org member
  get "/organizations/:organization_id/members/:username/permissions", operation_id: "orgs/get-member-permissions" do
    org, user = find_org!, this_user

    enforce_plan_supports_custom_org_roles!(org)

    control_access :read_org_member_permissions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if user && org.visible_user_ids_for(current_user, actor_ids: user.id).any?
      roles = user.org_roles_for(org)

      team_ids = org.teams_for(user).map(&:id_and_ancestor_ids).flatten.uniq
      teams = Team.where(id: team_ids)

      GitHub::PrefillAssociations.prefill_batch_method(teams, :org_roles)
      roles += teams.map { |team| team.org_roles }.flatten
      permissions = roles.uniq.map { |role| role.permissions.map(&:action) }.flatten.uniq

      deliver :org_member_permissions_hash, { user: user, organization: org, permissions: permissions }
    else
      deliver_error 404,
        message: "User does not exist or is not a member of the organization",
        documentation_url: @documentation_url
    end
  end

  # get if a user is a public member of :org
  get "/organizations/:organization_id/public_members/:username", operation_id: "orgs/check-public-membership-for-user" do
    org = find_org!
    @accepted_scopes = []
    control_access :get_public_member,
                   resource: org,
                   enforce_oauth_app_policy: false,
                   allow_integrations: true,
                   allow_user_via_granular_actor: true

    user = User.find_by_login params[:username]

    if org.public_member?(user)
      deliver_empty(status: 204)
    else
      deliver_error 404,
        message: "User does not exist or is not a public member of the organization",
        documentation_url: @documentation_url
    end
  end

  # publicize a user's membership in :org
  put "/organizations/:organization_id/public_members/:username", operation_id: "orgs/set-public-membership-for-authenticated-user" do
    receive_with_schema("organization-membership", "publicize")

    org = find_org!

    user = org ? org.find_direct_or_team_member_by_login(params[:username]) : nil

    forbid_unless_self(org, current_user, user)

    control_access :publicize_membership,
      resource: user,
      organization: org,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if GitHub.private_org_membership_visibility_enforced?
      deliver_error! 403, message:
        "You cannot publicize membership because private membership is enforced."
    end

    org.publicize_member(user)
    deliver_empty(status: 204)
  end

  def forbid_unless_self(org, publicizer, publicizee)
    if org.adminable_by?(publicizer) && publicizer != publicizee
      set_forbidden_message("Only the user can publicize their membership")
    end
  end

  # remove a user as a member of :org
  delete "/organizations/:organization_id/members/:username", operation_id: "orgs/remove-member" do
    # Introducing strict validation of the organization-membership.delete-member
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("organization-membership", "delete-member", skip_validation: true)

    control_access :v4_manage_org_users,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if org.has_full_trade_restrictions?
      status = changeset_active?(:change_remove_member_trade_compliance_response_status) ? 451 : 403
      deliver_error! status,
        message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
        documentation_url: GitHub.trade_controls_help_url
    end

    user = this_user

    if org.direct_or_team_member?(user)
      attempt_remove_member_from_org(user, org)
    else
      deliver_error 404, message: "Cannot find #{params[:username]}"
    end
  end

  # conceal a user's membership in :org
  delete "/organizations/:organization_id/public_members/:username", operation_id: "orgs/remove-public-membership-for-authenticated-user" do
    # Introducing strict validation of the organization-membership.conceal
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("organization-membership", "conceal", skip_validation: true)

    org = find_org!

    user = org.people.where(login: params[:username]).first

    control_access :conceal_membership,
      resource: user,
      organization: org,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if GitHub.public_org_membership_visibility_enforced?
      deliver_error! 403, message:
        "You cannot conceal membership because public membership is enforced."
    end

    org.conceal_member(user)
    deliver_empty(status: 204)
  end

  # add or update a user's membership with :org
  put "/organizations/:organization_id/memberships/:username", operation_id: "orgs/set-membership-for-user" do
    org, user = find_org!, this_user

    set_forbidden_message "You must be an admin to add or update an organization membership."

    if org.invitation_rate_limit_exceeded?
      deliver_error! 403,
        message: org.invitation_rate_limit_error_message,
        documentation_url: "/v3/orgs/members/#rate-limits"
    end

    control_access :v4_manage_org_users,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_not_blocked! current_user, user

    if user.organization?
      deliver_error! 422, message: "Members must be users, not organizations."
    end

    if user.bot?
      deliver_error! 422, message: "Members must be users, not bots."
    end

    if org.has_full_trade_restrictions?
      status = changeset_active?(:change_update_user_membership_trade_compliance_response_status) ? 451 : 403
      deliver_error! status,
        message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
        documentation_url: GitHub.trade_controls_help_url
    end

    # Introducing strict validation of the organization-membership.replace
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("organization-membership", "replace", skip_validation: true)
    requested_role = data["role"] || "member"

    if requested_role == "member" && current_user == user && org.adminable_by?(current_user)
      deliver_error! 403, message: "You cannot demote yourself. Admins must be demoted by another admin."
    end

    if %w(admin member).exclude?(requested_role)
      deliver_error! 422, message: "User must have a valid role."
    end

    if !org.business_or_org_has_seats_for?(user: user)
      error_code = :no_seat
    else
      legacy_owners_team = org.legacy_owners_team

      # Munge the passed role to work for our member updating and inviting
      # methods.
      if requested_role == "admin"
        role   = :admin
        action = :admin
      else
        role   = :direct_member
        action = :read
      end

      # Temporary backwards compatibility
      #
      # The org making this request has direct org membership enabled, so this
      # API will be updating the user's role in the organization.
      #
      # This block of code keeps the Owners team in sync if they're changing
      # an admin to a member or a member to an admin.
      teams = []
      if role == :admin
        if org.direct_or_team_member?(user)
          legacy_owners_team.add_member user if legacy_owners_team
        else
          teams = [legacy_owners_team].compact
        end
      elsif role == :direct_member
        attempt_remove_member_from_legacy_owners_team(user, legacy_owners_team)
      end

      if org.direct_member? user
        begin
          org.update_member(user, action: action)
        rescue Organization::NoAdminsError
          deliver_error! 403, message: "You can't demote the last admin to a member."
        end
      elsif invitation = org.pending_invitation_for(user)
        invitation.update_attribute(:role, role)
        if role == :admin && legacy_owners_team.present?
          invitation.add_team(legacy_owners_team, inviter: current_user)
        end

        # If invites are disabled, go ahead and accept any existing invites
        if GitHub.bypass_org_invites_enabled?
          invitation.accept
        end
      elsif OrganizationInvitation::OptOut.opted_out?(org: org, invitee: user)
        deliver_error! 422, message: "The request could not be processed."
      else
        if GitHub.bypass_org_invites_enabled?
          org.add_member(user, action: action, adder: current_user)
        elsif org.enterprise_managed_user_enabled?
          if emu_mismatch?(org, user)
            deliver_error! 403, message: "Only enterprise provisioned members can be added to this organization."
          else
            org.add_member(user, action: action, adder: current_user)
          end
        elsif user.is_enterprise_managed? && emu_mismatch?(org, user)
          deliver_error! 403, message: "This user cannot be added to this organization."
        elsif user.blocked_by? org
          deliver_error! 422, message: "You cannot invite a user who is blocked by the organization."
        else
          org.invite(user, inviter: current_user, role: role, teams: teams, invitation_source: :member)
        end
      end
    end

    if error_code.present?
      error = translate_error(error_code, org, @documentation_url)
      deliver_error(422, error)
    else
      deliver :org_membership_hash, org, user: user
    end
  end

  # get a user's membership of :org
  get "/organizations/:organization_id/memberships/:username", operation_id: "orgs/get-membership-for-user" do
    org, user = find_org!, this_user

    set_forbidden_message "You must be a member of #{org.login_for_api} to see membership information for #{user.login_for_api}."

    control_access :get_member,
      resource: org,
      member: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if org.membership_visible_via_api?(viewer: current_user, member: user)
      deliver :org_membership_hash, org, user: user
    else
      deliver_error 404
    end
  end

  delete "/organizations/:organization_id/memberships/:username", operation_id: "orgs/remove-membership-for-user" do
    # Introducing strict validation of the organization-membership.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("organization-membership", "delete", skip_validation: true)

    org, user = find_org!, this_user

    set_forbidden_message "You must be an admin to remove an organization membership."
    control_access :v4_manage_org_users,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitation = org.pending_invitation_for(user)

    if invitation.present? && invitation.cancelable_by?(current_user)
      invitation.cancel(actor: current_user)
      deliver_empty(status: 204)
    elsif org.member?(user)
      attempt_remove_member_from_org(user, org)
    else
      deliver_error 404, message: "Cannot find #{params[:username]}"
    end
  end

  private

  def filters
    params[:filter].try(:split, ",") || []
  end

  def wants_two_factor_audit?
    tfa_audits = %w[2fa_disabled 2fa_insecure]
    (filters & tfa_audits).any?
  end

  def can_view_private_members?
    access_allowed?(:get_member, resource: find_org, member: this_user, allow_integrations: true, allow_user_via_granular_actor: true)
  end

  def public_members_url
    api_url("/organizations/#{params[:organization_id]}/public_members/#{params[:username]}")
  end

  def role
    case params[:role]
    when "admin"
      :admin
    when "member"
      :member_without_admin
    end
  end

  def type_of_users_to_fetch
    org = find_org!

    if role.present?
      return role if org.direct_member?(current_user)
      return role if current_integration.present? && org.resources.members.readable_by?(current_user)
    end

    :all
  end

  # Private: Translate an error code to an API 422 response.
  #
  # error_code        - A Symbol error code.
  # org               - An Organization.
  # documentation_url - String url for documentation.
  #
  # Returns a Hash.
  def translate_error(error_code, org, documentation_url)
    response = {
      message: "Validation Failed",
      errors: [{ code: error_code, field: :user }],
      documentation_url: documentation_url,
    }

    case error_code
    when :blocked
      response[:message] = "User is blocked. #{GitHub.support_link_text}."
    when :org
      response[:message] = "Cannot add an organization as a member."
    when :no_seat
      response[:message] = "You must purchase at least one more seat to add this user as a member."
      response[:documentation_url] = "https://github.com/organizations/#{org.display_login}/settings/billing/seats"
    when :restricted_org
      response[:message] = ::TradeControls::Notices.notice_as_plaintext(:organization_account_restricted)
      response[:documentation_url] = GitHub.trade_controls_help_url
    end

    response
  end

  # Private: Try to remove the specified member from the specified org. This
  # will deliver an API response, so don't try to deliver another one after
  # calling this.
  #
  # You should set @documentation_url before calling this method, so that
  # deliver_error will pick it up if necessary.
  #
  # member - User to attempt to remove.
  # org    - Organization to remove the member from.
  #
  # Returns nothing.
  def attempt_remove_member_from_org(member, org)
    if org.member?(member)
      begin
        org.remove_member(member, background_team_remove_member: true)
      rescue Organization::NoAdminsError
        deliver_error 403, message: "Cannot remove the last owner"
      rescue Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError => error
        deliver_error 403, message: error.message
      else
        deliver_empty(status: 204)
      end
    else
      deliver_error 404, message: "Not a member"
    end
  end

  # Private: Try to remove the specified member from the specified legacy owners
  # team of the.
  #
  # member             - User to attempt to remove.
  # legacy_owners_team - Legacy owners team to remove the member from.
  #
  # Returns nothing.
  def attempt_remove_member_from_legacy_owners_team(member, legacy_owners_team)
    return if legacy_owners_team.nil?

    begin
      legacy_owners_team.remove_member(member)
    rescue Team::EmptyOwnersError
      deliver_error! 403, message: "You can't remove the last member of the owners team."
    end
  end

  # Private: Test if the organization and user belong to the same EMU enterprise
  #
  # org               - Organization having user added to it
  # user              - User being added to the organization
  #
  # Returns boolean
  def emu_mismatch?(org, user)
    return false unless org.enterprise_managed_user_enabled? || user.is_enterprise_managed?

    org.business != user.enterprise_managed_business
  end

  def enforce_plan_supports_custom_org_roles!(org)
    deliver_error! 422, message: "Feature not available for the #{org.login_for_api} organization." unless org.custom_roles_supported?
  end
end
