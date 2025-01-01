# typed: true
# frozen_string_literal: true

# This job is enqueued specifically for removing org admins, and is locked
# to one concurrent job per org, to prevent situations where multiple
# concurrent jobs can result in all org admins being unintentionally removed.
class RemoveOrgAdminJob < ApplicationJob
  queue_as :remove_org_member

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.seconds
  LOCK_KEY_PREFIX = "remove-org-admin-job:"

  MAX_RETRY_ATTEMPTS = 5

  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, jitter: 0.15, attempts: MAX_RETRY_ATTEMPTS do |job, error|
    Failbot.report(
      error,
      {
        "gh.job.retries" => job.executions,
        "gh.org.id" => job.arguments.first,
      }
    )
  end

  resolve_tenant_context do |org_id, user_id|
    org = Organization.find_by(id: org_id)
    next org.business if org&.business

    user = User.find_by(id: user_id)
    user&.enterprise_managed_business
  end

  def perform(org_id, user_id, options = {})
    return unless org = Organization.find_by(id: org_id)
    return unless user = User.find_by(id: user_id)

    lock!(org_id) do
      with_write do
        begin
          org.remove_member!(user, **options)
        rescue Organization::NoAdminsError
          # Ignore as this is unactionable.
        end
      end
    end
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  def lock!(org_id)
    restraint.lock!("#{LOCK_KEY_PREFIX}#{org_id}", MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
