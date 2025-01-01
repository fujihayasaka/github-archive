# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationMembershipsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_account_is_user

  layout "layouts/stafftools/user/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  ORG_AFFILIATIONS_ORDER = {
    admin: 1,
    member: 2,
    billing_manager: 3,
    outside_collaborator: 4
  }

  def index
    orgs = this_user.affiliated_organizations_with_roles.sort_by do |org, roles|
      [ORG_AFFILIATIONS_ORDER[roles.first], org.login]
    end.to_h
    orgs_owned = this_user.owned_organizations.sort_by(&:login)
    team_counts = orgs.keys.index_with do |org|
      teams_for(org).count
    end
    GitHub::PrefillAssociations.prefill_associations(orgs.keys, :sponsors_listing)
    paginated_orgs = orgs.keys.paginate(page: params[:orgs_page], per_page: params[:per_page] || 30)
    org_permissions = orgs.fetch_values(*paginated_orgs)

    render "stafftools/organization_memberships/index", locals: {
      orgs: paginated_orgs,
      orgs_permissions: org_permissions,
      orgs_owned: orgs_owned.paginate(page: params[:owned_page], per_page: params[:per_page] || 30),
      team_counts: team_counts,
      businesses: sorted_businesses,
      unaffiliated_businesses: unaffiliated_businesses
    }
  end

  def show
    org = this_user.organizations.find_by_login params[:id]

    fetch_audit_log_teaser org_query(org)

    render "stafftools/organization_memberships/show", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      org: org,
      teams: teams_for(org).sort_by { |t| t.name }
    }
  end

  def remove_user # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by_login(params[:id])

    begin
      if this_user.affiliated_with_organization?(org)
        if GitHub.guard_audit_log_staff_actor?
          GitHub.context.push(hide_staff_user: true)
          Audit.context.push(hide_staff_user: true)
        end

        org.remove_any_affiliation(this_user, actor: current_user)
      else
        return render_404
      end

      flash[:notice] = "Removed #{this_user} from the #{org} organization. It may take a few minutes to process."
    rescue Organization::NoAdminsError
      flash[:notice] = <<~STR
        Can't remove #{this_user} from the #{org} organization.
        #{this_user} is the last remaining owner.
      STR
    rescue Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError => error
      flash[:notice] = error.message
    end

    redirect_to stafftools_user_organization_memberships_path(this_user)
  end

  def enable_two_factor_requirement # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by_login(params[:id])
    if org.can_two_factor_requirement_be_enabled?
      GitHub.dogstats.increment "organization", tags: ["action:enable_two_factor_requirement"]
      EnforceTwoFactorRequirementOnOrganizationJob.perform_later(org, current_user)
      flash[:notice] = "Enabling two-factor authentication requirement."
    else
      flash[:error] = "Two-factor authentication requirement cannot be enabled. No organization admins have two-factor authentication enabled."
    end
    redirect_to stafftools_user_organization_memberships_path(this_user)
  end

  def disable_two_factor_requirement # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by_login(params[:id])
    GitHub.dogstats.increment "organization", tags: ["action:disable_two_factor_requirement"]

    org.disable_two_factor_requirement(log_event: true, actor: current_user)

    flash[:notice] = "Disabled two-factor authentication requirement."
    redirect_to stafftools_user_organization_memberships_path(this_user)
  end

  private

  def sorted_businesses
    return if GitHub.single_business_environment?

    if this_user.guest_collaborator?
      [this_user.enterprise_managed_business]
    else
      this_user.businesses.sort_by(&:slug)
    end
  end

  def unaffiliated_businesses
    ids = BusinessUserAccount.where(user: this_user).exclusive_unaffiliated_role.pluck(:business_id)
    return Business.none unless ids.any?
    Business.where(id: ids).sort_by(&:slug)
  end

  ORG_AUDIT_EVENTS = %w(
      action:org.invite_member
      action:org.cancel_invitation
      action:org.add_member
      action:org.update_member
      action:org.remove_member
      action:org.restore_member
      action:org.add_billing_manager
      action:org.remove_billing_manager
    )

  TEAM_AUDIT_EVENTS = %w(
    action:team.add_member
    action:team.remove_member
  )

  def kql_actions(actions)
    actions.map { |a| "'#{a.gsub("action:", "")}'" }.join(", ")
  end

  def this_user_query
    if driftwood_ade_query?(current_user)
      "webevents | where user_id == #{this_user.id} | where action in (#{kql_actions(ORG_AUDIT_EVENTS)})"
    else
      "user_id:#{this_user.id} AND (#{ORG_AUDIT_EVENTS.join(" OR ")})"
    end
  end

  def org_query(org)
    if driftwood_ade_query?(current_user)
      <<~KQL
        webevents
        | where org_id == #{org.id}
        | where user_id == #{this_user.id}
        | where action in (#{kql_actions(ORG_AUDIT_EVENTS + TEAM_AUDIT_EVENTS)})
      KQL
    else
      [
        "org_id:#{org.id}",
        "user_id:#{this_user.id}",
        "(#{(ORG_AUDIT_EVENTS + TEAM_AUDIT_EVENTS).join(" OR ")}",
      ].join(" AND ")
    end
  end

  def teams_for(org)
    org.teams_for(this_user).tap do |teams|
      GitHub::PrefillAssociations.prefill_associations(teams, :organization, available_records: [org])
    end
  end
end
