# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveUserFromOrganizationJob < ApplicationJob
  RetryableError = Class.new(StandardError)

  MAX_ATTEMPTS = 5

  queue_as :remove_user_from_org

  attr_reader :org_id, :user_id

  # Only a single unique instance of the job can be concurrently running
  # per org and user being removed
  locked_by timeout: 1.hour, key: -> (job) { "remove_user_from_org::#{job.arguments[0]}_#{job.arguments[1]}" }

  retry_on RetryableError, attempts: MAX_ATTEMPTS do |job, error|
    Failbot.report(error, org_id: job.org_id, user_id: job.user_id)
  end

  retry_on_dirty_exit

  resolve_tenant_context do |org_id|
    org = Organization.find_by(id: org_id)
    org&.business
  end

  def perform(org_id, user_id)
    @org_id = org_id
    @user_id = user_id

    organization = Organization.find(org_id)
    user = User.find(user_id)

    with_write { organization.remove_any_affiliation(user, actor: user) }
    increment_stats("user_removed_from_organization")
  rescue => error # rubocop:todo Lint/GenericRescue
    report_error!(error)
  end

  private

  def report_error!(error)
    Failbot.report!(error, org_id: org_id, user_id: user_id)

    if executions <= MAX_ATTEMPTS
      increment_stats("errored", tags: ["error:#{error.class.name}", "retryable:true"])
      raise RetryableError.new(error)
    else
      increment_stats("errored", tags: ["error:#{error.class.name}", "retryable:false"])
      raise error
    end
  end

  def increment_stats(key, tags: [])
    stat = stats_key(key)
    GitHub.dogstats.increment(stat, tags: tags)
  end

  def stats_key(suffix)
    "jobs.remove_user_from_org.#{suffix}"
  end
end
