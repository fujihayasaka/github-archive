# typed: true
# frozen_string_literal: true

class RemoveMembersTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  step :revoke_abilities do
    options = data[:options] || {}
    repo_ids = orchestration_team.direct_or_inherited_repo_ids(affiliation: :all)
    memberships = Team::Membership::AbilitiesRemover.new(
      orchestration_team,
      user_ids,
      repo_ids,
      send_notification: options[:send_notification] || true,
      team_destroyed: options[:team_destroyed] || false,
    )

    memberships.bulk_remove(users: users, queue_delete_jobs: options[:queue_delete_jobs] || true, caller_type: data[:caller_type])
  end

  job_start

  step :instrument_remove_member do
    users.each do |user|
      # TODO: can batch instrumentation later
      exclude_audit_log_instrumentation = GitHub.esm_enabled? && data[:caller_type] == :enterprise_team
      orchestration_team.instrument_remove_member(
        user,
        exclude_audit_log_instrumentation: exclude_audit_log_instrumentation
      )
    end
  end

  step :remove_organization_memberships do
    options = data[:options] || {}
    return if options[:skip_remove_organization_memberships] # Don't execute for BusinessTeam
    # TODO: implement when adding support for non-business teams without skip_create_organization_memberships
  end

  step :remove_team_subscriptions do
    team_ids = orchestration_team.ancestor_ids + [team_id]
    Team::Destruction::DestroySubscriptionsOperation.new(user_ids, team_ids, orchestration_team.class.name).execute
  end

  step :deny_fork_collab_state_for_user_pull_requests do
    users.each do |user|
      DenyForkCollabStateForUserPullRequestsJob.perform_later(
        user_id: user.id,
        resource_id: team_id,
        resource_class: orchestration_team.class.name,
      )
    end
  end

  step :clear_user_contribution_caches do
    Contribution.bulk_clear_caches_for_users(users.to_a, context: "bulk_remove_org_team_members")
  end

  step :update_license_usage do
    options = data[:options] || {}
    return if GitHub.single_business_environment? || options[:skip_license_usage_update] == true

    business&.update_license_usage
  end
end
