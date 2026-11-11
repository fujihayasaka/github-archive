# typed: strict
# frozen_string_literal: true

class BusinessOrchestrationRemoveOrgUserEmailSettingsJob < ApplicationJob
  queue_as :business_orchestration_remove_org_user_email_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_TTL = T.let(5.minutes, Integer)
  GLOBAL_LOCK_KEY = T.let("business_orchestration_remove_org_user_email_settings", String)

  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(GLOBAL_LOCK_KEY, GitHub.business_orchestration_remove_org_user_email_settings_job_limit, LOCK_TTL) do
      block.call
    end
  end

  sig { params(orchestration: RemoveOrganizationMembersCleanupBusinessOrchestration, organization_ids: T::Array[Integer], user_ids: T::Array[Integer]).void }
  def perform(orchestration, organization_ids, user_ids)
    GitHub.logger.info("BusinessOrchestrationRemoveOrgUserEmailSettingsJob started", {
      "gh.business.id": T.must(orchestration.business).id,
      "gh.business.orchestration.id": orchestration.id,
      "gh.organization.ids": organization_ids,
      "gh.user.ids": user_ids,
    })

    users = User.where(id: user_ids)
    return if users.empty?

    organizations = Organization.where(id: organization_ids)
    return if organizations.empty?

    organizations.each do |org|
      return if T.must(orchestration.business).kill_switch_enabled?("BusinessOrchestrationRemoveOrgUserEmailSettingsJob")
      users.each do |user|
        with_write { org.remove_user_email_setting_for_org(user) }
      end
    end

    GitHub.logger.info("BusinessOrchestrationRemoveOrgUserEmailSettingsJob finished", {
      "gh.business.id": T.must(orchestration.business).id,
      "gh.business.orchestration.id": orchestration.id,
      "gh.organization.ids": organization_ids,
      "gh.user.ids": user_ids,
    })
  end
end
