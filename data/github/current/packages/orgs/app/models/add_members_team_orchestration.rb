# typed: true
# frozen_string_literal: true

class AddMembersTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  step :revoke_new_hire_accesses do
    return if !GitHub.new_staff_precautions? || !orchestration_team.github_employees_team?
    users.each { |user| user.revoke_new_hire_accesses }
  end

  step :create_abilities do
    if FeatureFlag.vexi.enabled_or_raise?("authz_no_bulk_grant_transaction") # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      orchestration_team.bulk_grant_members(users.to_a, grantor: actor, skip_revoke: true)
    else
      Ability.transaction do
        orchestration_team.bulk_grant_members(users.to_a, grantor: actor)
      end
    end
  end

  step :create_organization_memberships do
    options = data[:options] || {}
    return if options[:skip_create_organization_memberships] # Don't execute for BusinessTeam
    # TODO: implement when adding support for non-business teams without skip_create_organization_memberships
  end

  job_start

  step :cancel_pending_team_membership_requests do
    options = data[:options] || {}
    return if options[:skip_create_organization_memberships] # Don't execute for BusinessTeam
    # TODO: implement when adding support for non-business teams without skip_create_organization_memberships
  end

  step :instrument_add_members do
    orchestration_team.instrument_add_members(users.to_a, actor, data[:caller_type])
  end

  step :add_dashboard_notices do
    if FeatureFlag.vexi.enabled?(:team_bulk_add_dashboard_deadlock_retry, business, default: false)
      retry_on_deadlock do
        DashboardNoticesStore.bulk_add(user_ids, :org_newbie)
      end.rescue do |result|
        Failbot.report(result, operation: :activate_notice, notice_name: :org_newbie, app: "github-user")
        GitHub::Result.error result
      end
    else
      DashboardNoticesStore.bulk_add(user_ids, :org_newbie)
        .rescue do |result|
          Failbot.report(result, operation: :activate_notice, notice_name: :org_newbie, app: "github-user")
          GitHub::Result.error result
        end
    end
  end

  step :auto_subscribe_users do
    options = data[:options] || {}
    should_auto_subscribe_user = data[:caller_type] != :enterprise_team
    users.each do |user|
      user.reset_notices
      orchestration_team.auto_subscribe_user user if should_auto_subscribe_user

      if !user.suspended? && actor != user && orchestration_team.send_user_added_notifications? && options[:send_notification] != false
        TeamsMailer.team_added(user, orchestration_team, actor).deliver_later(queue: "team_member_added_emails")
      end
    end
  end

  step :clear_user_contribution_caches do
    Contribution.bulk_clear_caches_for_users(users.to_a, context: "bulk_add_org_team_members")
  end

  step :update_license_usage do
    options = data[:options] || {}
    return if GitHub.single_business_environment? || options[:skip_license_usage_update] == true

    business&.update_license_usage
  end
end
