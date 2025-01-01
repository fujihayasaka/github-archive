# typed: true
# frozen_string_literal: true

class Stafftools::TeamsController < StafftoolsController
  include FeatureFlagHelper

  GROUP_SYNCER_RPC_TIMEOUT = 8.0

  before_action :ensure_user_exists
  before_action \
    :ensure_team_exists,
    except: [:index, :owners, :add_owner, :demote_owner, :direct_members, :guest_collaborators,
             :outside_collaborators, :pending_collaborators, :invitations, :failed_invitations,
             :invitation_opt_outs, :set_invitation_rate_limit, :reset_invitation_rate_limit,
             :remove_invitation_opt_out]

  layout "layouts/stafftools/organization/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:external_groups]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:group_sync_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:failed_invitations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:direct_members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:guest_collaborators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:invitations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:outside_collaborators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:owners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:pending_collaborators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:database]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:requests]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:external_members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:invitation_opt_outs]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index, :external_groups, :failed_invitations, :requests, :guest_collaborators,
      :pending_collaborators, :direct_members, :outside_collaborators, :owners, :invitations, :repositories,
      :external_members, :invitation_opt_outs, :members, :database],
    optional: true

  def index
    moderator_users = this_user.moderators.select { |moderator| moderator.is_a?(User) }
    moderator_teams = this_user.moderators - moderator_users

    render "stafftools/teams/index", locals: {
      num_admins:      this_user.admins.count,
      num_members:     this_user.members_count,
      num_guest_collaborators: this_user.guest_collaborators.count,
      num_outside_collaborators: this_user.outside_collaborators_count,
      num_pending_collaborators: this_user.repository_invitations.excluding_expired.count,
      num_invitations: this_user.pending_invitations.count,
      num_failed_invitations: this_user.active_failed_invitations_count,
      num_opted_out_invitations: OrganizationInvitation::OptOut.grouped_by_invitation(org: this_user).count,
      num_moderator_users: moderator_users.count,
      num_moderator_teams: moderator_teams.count,
      teams: Stafftools::Team.for_organization(
        this_user,
        query: params[:query],
        page: current_page
      )
    }
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/teams/database"
  end

  def owners # rubocop:todo GitHub/UseRestfulActions
    audit_log_query = if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        #{this_user.audit_log_kql_query}
        | where data.permission == "admin" or data.old_permission == "admin"
        | where #{org_member_audit_log_actions_kql}
      KQL
    else
      [
        this_user.audit_log_query,
        "action:org.*member",
        "(data.permission:admin OR data.old_permission:admin)",
      ].join(" ")
    end
    fetch_audit_log_teaser audit_log_query

    owners = this_user.admins.includes(:profile).order("login ASC").paginate(page: current_page)
    # query gets sanitized in the like_login_or_profile_name scope
    query = params[:query].to_s.strip.downcase
    owners = owners.like_login_or_profile_name(query) if query.present?
    render "stafftools/teams/owners", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      users: owners,
      all_org_owners: this_user.admins.order("login ASC").includes(:profile)
    }
  end

  def add_owner # rubocop:todo GitHub/UseRestfulActions
    GitHub.context.push(hide_staff_user: true)
    Audit.context.push(hide_staff_user: true)
    user_to_add_as_owner = User.find_by_login(params[:login])
    reason = params[:reason]
    case
    when reason.nil?
      flash[:error] = "Nice try, you need to provide both a username and a reason"
    when reason.strip.empty?
      flash[:error] = "Nice try, you need to type a meaningful reason"
    when user_to_add_as_owner.nil?
      flash[:error] = "Nice try, there isn't anybody called #{params[:login]}"
    when user_to_add_as_owner.organization?
      flash[:error] = "#{user_to_add_as_owner.login} is an organization"
    when this_user.adminable_by?(user_to_add_as_owner)
      flash[:error] = "#{user_to_add_as_owner.login} already owns #{this_user.login}"
    when !this_user.two_factor_requirement_met_by?(user_to_add_as_owner)
      flash[:error] = "#{user_to_add_as_owner.login} doesn't meet the 2FA requirement of #{this_user.login}"
    when !this_user.meets_sso_requirements?(user: user_to_add_as_owner)
      flash[:error] = "#{user_to_add_as_owner.login} doesn't meet the SSO requirements of #{this_user.login}"
    when user_to_add_as_owner.is_enterprise_managed? && !this_user.business&.enterprise_managed_user_enabled?
      # If you add an EMU user from another EMU enterprise, it usually fails the previous SSO check so here we just focus on checking
      # https://github.com/github/github/blob/8539c3c4e98d02ec49d6279616467119e2d7275c/packages/app_security/app/models/user/permissions_dependency.rb#L60
      # To avoid a 500 error. We reuse the same message.
      # If we ever hit https://github.com/github/github/blob/8539c3c4e98d02ec49d6279616467119e2d7275c/packages/app_security/app/models/user/permissions_dependency.rb#L73-L75
      # and hit another 500, we can add that check here too later.
      flash[:error] = "Can't grant permissions to an Enterprise Managed User (#{user_to_add_as_owner.login}) over an external Organization (#{this_user.login})"
    when this_user.member?(user_to_add_as_owner)
      Audit.context.push(note: reason) do
        this_user.update_member(user_to_add_as_owner, action: :admin, updater: current_user)
      end
      flash[:notice] = "#{user_to_add_as_owner.login} was already a member of #{this_user.login} and they have been promoted to an owner"
    else
      Audit.context.push(note: reason) do
        this_user.add_admin(user_to_add_as_owner, adder: current_user)
      end
      flash[:notice] = "#{user_to_add_as_owner.login} added as owner to #{this_user.login}"
    end
    redirect_to owners_stafftools_user_path(this_user)
  end

  def demote_owner # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_user.login == "dsp-testing"

    GitHub.context.push(hide_staff_user: true)
    Audit.context.push(hide_staff_user: true)
    owner_to_demote = User.find_by_login(params[:login])

    reason = params[:reason]
    case
    when reason.nil?
      flash[:error] = "Nice try, you need to provide both a username and a reason"
    when reason.strip.empty?
      flash[:error] = "Nice try, you need to type a meaningful reason"
    when owner_to_demote.nil?
      flash[:error] = "Nice try, there isn't anybody called #{params[:login]}"
    when owner_to_demote.organization?
      flash[:error] = "#{owner_to_demote.login} is an organization"
    when !this_user.two_factor_requirement_met_by?(owner_to_demote)
      flash[:error] = "#{owner_to_demote.login} doesn't meet the 2FA requirement of #{this_user.login}"
    when !this_user.meets_sso_requirements?(user: owner_to_demote)
      flash[:error] = "#{owner_to_demote.login} doesn't meet the SSO requirements of #{this_user.login}"
    when !this_user.adminable_by?(owner_to_demote)
      flash[:error] = "#{owner_to_demote.login} is not an owner of #{this_user.login}. You can't demote them any further."
    else
      begin
        Audit.context.push(note: reason) do
          this_user.update_member(owner_to_demote, action: :read, updater: current_user)
        end
      rescue Organization::NoAdminsError
        flash[:error] = "You can't remove the organization's last admin."
      else
        flash[:notice] = "#{owner_to_demote.login} has been demoted to a member of #{this_user.login}"
      end
    end
    redirect_to owners_stafftools_user_path(this_user)
  end

  def direct_members # rubocop:todo GitHub/UseRestfulActions
    query = "#{this_user.audit_log_query} action:org.*member"
    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        #{this_user.audit_log_kql_query}
        | where #{org_member_audit_log_actions_kql}
      KQL
    end
    fetch_audit_log_teaser query

    users = this_user.members(limit: Organization::MEGA_ORG_MEMBER_THRESHOLD).includes(:profile).order("login ASC").paginate(page: current_page)
    query = params[:query].to_s.strip.downcase  # query will get sanitized in the like_login_or_profile_name scope
    users = users.like_login_or_profile_name(query) if query.present?

    render "stafftools/teams/direct_members", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      users: users
    }
  end

  def guest_collaborators # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_user.enterprise_managed_user_enabled?

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    guest_collaborators = this_user.guest_collaborators(query).order("login ASC").paginate(page: current_page)

    render "stafftools/teams/guest_collaborators", locals: {
      query: @query,
      more_results: @more_results,
      users: guest_collaborators
    }
  end

  def outside_collaborators # rubocop:todo GitHub/UseRestfulActions
    users = this_user.outside_collaborators.includes(:profile).order("login ASC").paginate(page: current_page)
    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    users = users.like_login_or_profile_name(query) if query.present?

    render "stafftools/teams/outside_collaborators", locals: { users: users }
  end

  def pending_collaborators # rubocop:todo GitHub/UseRestfulActions
    scope = this_user.repository_invitations.preload(:repository, :invitee).excluding_expired

    filter_seats = params[:is_occupying_seat] == "true"
    if filter_seats
      scope = scope.where(invitee_id: this_user.private_repo_non_collaborator_invitee_ids).or(
        scope.where(
          email: this_user.private_repo_non_user_invited_emails - this_user.pending_invited_non_user_emails
        )
      )
    end

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].strip.downcase) if params[:query]
    if query.present?
      like_login_ids = User.where(id: scope.pluck(:invitee_id))
        .like_login_or_profile_name(query).pluck(:id)
      like_email_ids = scope.where.not(email: nil)
        .where(["email LIKE :query", { query: "%#{query}%" }]).pluck(:id)
      scope = scope.where(invitee_id: like_login_ids).or(scope.where(id: like_email_ids))
    end

    collaborator_invitations = scope.paginate(page: current_page)

    view = Stafftools::Organization::Teams::PendingCollaboratorsView.new \
      collaborator_invitations: collaborator_invitations,
      filter_seats: filter_seats,
      query: params[:query]
    render "stafftools/teams/pending_collaborators", locals: {
      collaborator_invitations: collaborator_invitations, view: view
    }
  end

  def invitations # rubocop:todo GitHub/UseRestfulActions
    query = [
      this_user.audit_log_query,
      "(action:org.invite_member OR action:org.cancel_invitation OR action:org.rate_limited_invites OR action:org.*_custom_invitation_rate_limit)",
    ].join(" ")
    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        #{this_user.audit_log_kql_query}
        | where action in ("org.invite_member", "org.cancel_invitation", "org.rate_limited_invites") or action matches regex "org.*_custom_invitation_rate_limit"
      KQL
    end
    fetch_audit_log_teaser query

    render "stafftools/teams/invitations", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      invitations: this_user.pending_invitations.paginate(page: current_page),
      rate_limit_policy: OrganizationInvitation::RateLimitPolicy.new(this_user)
    }
  end

  def failed_invitations # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/teams/failed_invitations", locals: {
      invitations: this_user.active_failed_invitations.paginate(page: current_page)
    }
  end

  def invitation_opt_outs # rubocop:todo GitHub/UseRestfulActions
    invitation_opt_outs = OrganizationInvitation::OptOut.grouped_by_invitation(org: this_user)

    render "stafftools/teams/invitation_opt_outs", locals: {
      invitation_opt_out_groups: invitation_opt_outs,
    }
  end

  # Remove an opt out for invitations from an organization
  #
  # invitation - the `id` of the invitation that the user opted out from
  def remove_invitation_opt_out # rubocop:todo GitHub/UseRestfulActions
    invite = params[:invitation]
    opt_outs = OrganizationInvitation::OptOut.where(organization_invitation_id: invite)

    if opt_outs.present?
      opt_outs.each do |opt_out|
        opt_out.destroy
      end

      instrument("staff.remove_opt_out", user: this_user, invitation_id: invite)
      flash[:notice] = "Opt outs removed for invitation ##{invite}"
      redirect_to :back
    else
      flash[:error] = "Whoops. There aren't any opt outs for that invitation."
      redirect_to :back
    end
  end

  def set_invitation_rate_limit # rubocop:todo GitHub/UseRestfulActions
    policy = OrganizationInvitation::RateLimitPolicy.new(this_user)
    result = policy.set_custom_limit(
      params[:custom_rate_limit],
      expires_at: params[:custom_rate_limit_expires_at]
    )

    if result[:success]
      with_expiry = if result[:expires_at].present?
        " and will expire at #{result[:expires_at]}"
      end
      flash[:notice] = "Custom rate limit policy applied#{with_expiry}!"
    else
      if result[:errors].present?
        flash[:error] = result[:errors].to_sentence
      else
        flash[:error] = "There was a problem parsing the rate limit. Please use numbers only, without commas."
      end
    end

    redirect_to invitations_stafftools_user_url(this_user)
  end

  def reset_invitation_rate_limit # rubocop:todo GitHub/UseRestfulActions
    policy = OrganizationInvitation::RateLimitPolicy.new(this_user)

    policy.clear_custom_limit

    flash[:notice] = "Custom rate limit policy removed!"
    redirect_to invitations_stafftools_user_url(this_user)
  end

  def show
    query = "data.team_id:#{this_team.id}"
    if GitHub.driftwood_ade_queries_enabled?
      query = "webevents | where org_id == #{this_team.organization&.id} and data.team_id == '#{this_team.id}'"
    end
    fetch_audit_log_teaser(query)

    # must check both externally_managed? and external_group_team since teams using Team Sync feature
    # in standard GHEC (non-EMUs) are also externally_managed? but do not have an external_group_team
    external_group_team = this_team.external_group_team if this_team.externally_managed?
    if external_group_team
      mismatched_memberships = external_group_team.calculate_group_team_mismatches
      memberships_match = mismatched_memberships.values.all?(&:empty?)
      group_member_ids_not_in_team = mismatched_memberships[:group_member_ids_not_in_team].paginate(page: params[:group_members_page])
      team_member_ids_not_in_group = mismatched_memberships[:team_member_ids_not_in_group].paginate(page: params[:team_members_page])
    end

    render "stafftools/teams/show", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      num_repos:    this_team.repositories_scope.count,
      num_members:  this_team.members_scope_count,
      num_requests: this_team.pending_team_membership_requests.count,
      ancestors:    this_team.ancestors,
      child_teams_count: this_team.descendants.count,
      external_groups_count: this_team.group_mappings.count,
      memberships_match: memberships_match,
      group_member_ids_not_in_team: group_member_ids_not_in_team,
      group_members_not_in_team: User.where(id: group_member_ids_not_in_team),
      team_member_ids_not_in_group: team_member_ids_not_in_group,
      team_members_not_in_group: User.where(id: team_member_ids_not_in_group),
    }
  end

  def group_sync_status # rubocop:todo GitHub/UseRestfulActions
    tenant = this_team.organization&.team_sync_tenant
    status = ""
    synced_at = ""
    unless tenant&.team_sync_enabled?
      render partial: "stafftools/teams/team_sync_status", locals: {
        mappings: nil, status: status, synced_at: synced_at
      }
      return
    end

    mappings = this_team.group_mappings

    if mapping = mappings.first
      status = mapping.status
      synced_at = mapping.synced_at.to_s if mapping.synced_at.present?
    end

    render partial: "stafftools/teams/team_sync_status", locals: {
      mappings: mappings, status: status, synced_at: synced_at
    }
  end

  def members # rubocop:todo GitHub/UseRestfulActions
    members_scope = this_team.members_scope.order("login ASC").includes(:profile)
    current_page_of_members_scope = members_scope.paginate(page: current_page)

    direct_members = Set.new(this_team
                               .members_scope(membership: :immediate)
                               .where(id: current_page_of_members_scope.map(&:id)),
                            )

    render "stafftools/teams/members", locals: {
      team_maintainers: this_team.maintainers,
      org_admins: this_user.direct_admins,
      all_members: members_scope,
      current_page_of_members: current_page_of_members_scope,
      direct_members: direct_members
    }
  end

  def external_members # rubocop:todo GitHub/UseRestfulActions
    all_members = []
    current_page_of_members = []

    # pull from RPC endpoint
    begin
      client = GroupSyncer.client_with_timeout([GROUP_SYNCER_RPC_TIMEOUT, params[:timeout_override].to_f].max)
      response = client.list_group_members(team_id: this_team.global_relay_id, group_id: params[:group_id])
      if response.error
        flash[:error] = "An error occurred while fetching group data, please try again"
      else
        all_external_members = this_team.matched_external_members(response.data.members)

        current_page_of_members_scope = all_external_members.paginate(page: current_page)

        all_members = all_external_members
        current_page_of_members = current_page_of_members_scope
      end
    rescue Faraday::TimeoutError
      flash[:error] = "Operation timed out. Check group_members_count in status logs to to see if this group exceeds max permissible limit (5994) on group size for team-sync."
    end

    render "stafftools/teams/external_members", locals: {
      team_maintainers: this_team.maintainers,
      org_admins: this_user.direct_admins,
      all_members: all_members,
      current_page_of_members: current_page_of_members
    }
  end

  def child_teams # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/teams/child_teams", locals: {
      child_teams: this_team.descendants.paginate(page: current_page),
    }
  end

  def external_groups # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/teams/external_groups", locals: {
      external_groups: this_team.group_mappings.paginate(page: current_page),
    }
  end

  def reconcile # rubocop:todo GitHub/UseRestfulActions
    if this_team.externally_managed? && this_team.enterprise_managed_user_enabled?
      external_group_id = this_team.external_group_team.external_group_id
      team_id = this_team.id
      ExternalGroupTeamReconcileJob.perform_later(external_group_id: external_group_id, team_id: team_id, caller: self.class.name)
      flash[:notice] = "Reconciliation started for team: #{this_team.name}"
    else
      flash[:error] = "Unable to reconcile team. Please ensure that team is externally managed and linked to an IDP group."
    end

    redirect_to stafftools_user_teams_path(this_team.organization)
  end

  def repositories # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/teams/repositories", locals: {
      repos: Stafftools::Repository.for_team(this_team, current_page),
    }
  end

  def requests # rubocop:todo GitHub/UseRestfulActions
    requests = this_team.pending_team_membership_requests
      .includes(requester: :profile)
      .paginate(page: current_page)
    render "stafftools/teams/requests", locals: { requests: requests }
  end

  def sync # rubocop:todo GitHub/UseRestfulActions
    if this_team.externally_managed?
      rpc_response = GroupSyncer.client.sync_team(
        org_id: this_team.organization.global_relay_id,
        team_id: this_team.global_relay_id,
      )

      if rpc_response.error
        flash[:error] = "Team Sync Failed CODE: #{rpc_response.error.code} MSG: #{rpc_response.error.msg}"
      else
        flash[:notice] = "Team Sync Requested for #{this_team.name}"
      end

    else
      flash[:error] = "Team Sync is not configured for #{this_team.name}"
    end

    redirect_to stafftools_user_teams_path(this_team.organization)
  end

  # TODO: Migrate this action to be RESTful in own controller
  def migration_override # rubocop:todo GitHub/UseRestfulActions
    repository = if FeatureFlag.vexi.enabled?(:repos_domain_stafftools, default: false)
      if this_team.repository_id
        T.cast(Repositories.domain.by_id(this_team.repository_id), T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
      end
    else
      Repository.find_by(id: this_team.repository_id)
    end
    unless repository
      return redirect_to :back, flash: { error: "Repository not found" }
    end

    ConvertTeamDiscussionsToDiscussionsJob.perform_later(
      actor: current_user,
      team: this_team,
      repository: repository,
      include_private: this_team.private_posts_migrated
    )

    flash[:notice] = "Enqueued a new migration job, check back in a few minutes."
    redirect_to :back
  end

  private def org_member_audit_log_actions_kql
    action_pattern = /\Aorg\..*member\z/
    actions = Audit::ACTIONS_CRUD.select { |key, _| key.match(action_pattern) }.keys
    actions.map { |key| "action == \"#{key}\"" }.join(" or ")
  end
end
