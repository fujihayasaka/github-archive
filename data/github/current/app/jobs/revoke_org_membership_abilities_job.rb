# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RevokeOrgMembershipAbilitiesJob < ApplicationJob
  queue_as :revoke_org_membership_abilties
  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on StandardError

  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong,
    wait: :polynomially_longer, attempts: 20

  DEPENDENT_JOBS = [
    -> (org, user) { RemoveOrgMemberForksJob.enqueue(org, user) },
    -> (org, user) { RemoveOrgMemberWatchedRepositoriesJob.enqueue(org, user) },
    -> (org, user) { RemoveOrgMemberRepositoryStarsJob.enqueue(org, user) },
    -> (org, user) { RemoveOrgMemberIssueAssignmentsJob.perform_later(org, user) },
    -> (org, user) { RemoveOrgMemberVulnerabilityManagementJob.enqueue(org, user) },
    -> (org, user) {
      packages = org.packages
      packages.each_slice(100) do |package_batch|
        RemoveOrgMemberPackageAccessV2Job.perform_later(user, package_batch) unless GitHub.enterprise?
      end
    },
    -> (org, _) {
      IntegrationInstallation.where(target_id: org.id).each do |installation|
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation.id)
      end
    },
    -> (org, user) {
      if org.business && !GitHub.single_business_environment?
        BusinessMembershipCleanupJob.perform_later(org.business, user_ids: [user.id]) if !org.business.enterprise_managed_user_enabled?
        org.business.update_license_usage
      end
    },
    -> (org, _user) {
      TradeControls::OrganizationComplianceCheckJob.perform_later(org.id, reason: :organization_admin)
    },
    ->  (org, user) { RevokeOrgAppsManagementGrantsJob.perform_later(org, user) },
  ].freeze

  resolve_tenant_context do |organization_id, user_id|
    org = Organization.find_by(id: organization_id)
    next org.business if org&.business

    user = User.find_by(id: user_id)
    user&.enterprise_managed_business
  end

  def perform(organization_id, user_id, queue_delete_jobs = true, opts = {})
    org = Organization.find_by(id: organization_id)
    user = User.find_by(id: user_id)
    return unless org && user

    repo_ids = org.visible_repositories_for(user, batched: true).pluck(:id)

    org.teams_for(user).each do |team|
      with_write { team.remove_member(user, force: true, send_notification: false, queue_delete_jobs: false) }
    end

    # Remove Organization UserRole assignments
    user_role_revoke_retry_count = 3
    begin
      with_write { Permissions::Granters::RoleGranter.new(actor: user, target: org).revoke_if_exists! }
    rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
      # In practice revoke failures shouldn't happen.
      (user_role_revoke_retry_count -= 1) && retry if user_role_revoke_retry_count > 0
      raise # Re=raise the same error
    end

    unless opts[:revoke_performed_in_orchestration]
      Ability.throttle do
        with_write { org.remove_member_without_callbacks_and_notifications(user, background: false) }
      end
    end

    OrganizationCollaborator.update_for_org_and_user(org, user) if org.feature_flag_enabled?(:collaborator_cache_write, default: false) || org.business&.feature_flag_enabled?(:collaborator_cache_write, default: false)

    # Dependent jobs: Must be run after the user's abilities have been
    # revoked.
    DEPENDENT_JOBS.each { |job| job.call(org, user) }

    GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
      user: user,
      repository_ids: repo_ids,
    })
  end
end
