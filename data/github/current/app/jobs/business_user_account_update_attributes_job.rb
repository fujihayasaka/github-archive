# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessUserAccountUpdateAttributesJob < ApplicationJob
  queue_as :business_user_account_update_attributes

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "business-user-account-update-attributes-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes
  # P99 for the job is 30 seconds. Restraint lock will prevent the job from running simultaneously.
  ENQUEUE_INTERVAL = 30.seconds.to_i

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_ERRORS = [
    ActiveRecord::RecordNotFound,
    GitHub::Restraint::UnableToLock,
  ].freeze

  retry_on(*RETRYABLE_ERRORS, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS) do |_job, error|
    Failbot.report(error)
  end

  resolve_tenant_context do |args|
    if args.is_a?(Business)
      args
    else
      Business.find_by(id: args[:business_id])
    end
  end

  # This job takes information about user accounts from the business, and saves that information to the user accounts.
  #
  # Only one job will run at a time for each business. If another job is already running, this job will queue
  # another job to run when the current job finishes. This is to prevent thousands of jobs from being queued
  # when a large business is updated.
  #
  # business - Required Business for which BusinessUserAccounts will be updated
  # user_account_ids - Optional Array of Integers to restrict update to a set of
  #                    BusinessUserAccounts
  def perform(business = nil, business_id: nil, user_account_ids: nil)
    @business = business || Business.find_by(id: business_id)
    return unless @business.present?
    return unless @business.include_attributes_on_user_account?
    return if @business.kill_switch_enabled?(self.class.name, feature_flag: :enterprise_teams_killswitch, log_fields: {
      "gh.business.user_account_ids": user_account_ids,
    })

    lock!(@business.id) do
      # A single user account can have multiple updates. In order to avoid deadlocks, save each update in a separate transaction.
      user_attributes = BusinessUserAccount::UpdateAttributes.new(business: @business, user_account_ids: user_account_ids)

      with_write do
        user_attributes.save_roles
        user_attributes.save_licenses
        user_attributes.save_cost_centers
      end

      # Check if this job is only processing a subset of the required updates
      if user_attributes.updates_exceed_batch_size?
        BusinessUserAccountUpdateAttributesJob.enqueue(@business)
      end
    end
  end

  # Public: Enqueue a job to update the user accounts for a business. Will run immediately, and will queue another job
  # to run when the current job finishes if another job is already running.
  #
  # business - Required Business for which BusinessUserAccounts will be updated
  # user_account_ids - Optional Array of Integers to restrict update to a set of
  #                    BusinessUserAccounts
  #
  # Returns nothing
  def self.enqueue(business, user_account_ids: nil)
    args = { business_id: business.id, user_account_ids: user_account_ids }
    enqueue_once_per_interval(kwargs: args, interval: ENQUEUE_INTERVAL)
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(business_id)
    restraint_key = "#{LOCK_KEY}#{business_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
