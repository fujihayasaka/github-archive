# typed: strict
# frozen_string_literal: true

class BusinessUpdateLicenseUsageJob < ApplicationJob
  extend T::Sig

  queue_as :business_update_license_usage

  class RecordAlreadyExists < StandardError; end

  MAX_JOB_ATTEMPTS = 5
  CACHE_KEY_PREFIX = "github:jobs:business_update_license_usage"
  CACHE_TTL = T.let(3.minutes, ActiveSupport::Duration)
  retry_on Faraday::Error,
    ActiveRecord::RecordNotFound,
    RecordAlreadyExists,
    wait: :polynomially_longer,
    attempts: MAX_JOB_ATTEMPTS do |_job, error|
      raise error unless error.is_a?(ActiveRecord::RecordNotFound)

      # We retry on ActiveRecord::RecordNotFound because we want to ensure replication delay is not causing the record
      # to be missing. However, we don't want to raise an error if the record is not found because the record may have
      # been deleted at the time of the job running.
      if error.is_a?(ActiveRecord::RecordNotFound)
        GitHub.logger.error(
          exception: error,
          "code.namespace": self.class.name,
          "code.method": "perform",
        )
        GitHub.dogstats.increment("business_update_license_usage_job.record_not_found")
      end
    end
  retry_on_dirty_exit

  resolve_tenant_context do |business_id|
    Business.including_deleted.find(business_id)
  end

  # This job previously took in a business object parameter. We have transitioned to using business_id so that we can
  # bypass the default business scope of not including soft deleted businesses. This lets us avoid RecordNotFound
  # errors when we are given a soft deleted business by scoping with including_deleted.
  sig { params(business_id: Integer).void }
  def perform(business_id)
    return unless business_id.present?
    return if GitHub.single_business_environment?

    Failbot.push(business_id: business_id)

    business = T.let(Business.including_deleted.find(business_id), Business)

    if business.deleted?
      GitHub.logger.info(
        "Attempted to update license usage for soft deleted business",
        "code.namespace": self.class.name,
        "code.method": "perform",
      )
      GitHub.dogstats.increment("business_update_license_usage_job.soft_deleted_business")
      return
    end

    # This job runs immediately. However, if we fail to acquire the lock, we set a flag to message to the
    # actively running job to schedule another job. During high load, this means we skip jobs if a job is already
    # running, and for N jobs that are skipped, we schedule 1 extra job to ensure that license counts are up to date.
    lock_acquired = set_job_running(true, business: business)
    if !lock_acquired
      set_run_again(true, business: business)
      GitHub.logger.info("license usage update requested", {
        "gh.business.id": business_id,
        "gh.business.slug": business.slug,
        "gh.license_usage.completed": false,
      })
      return
    end
    begin
      generated_at = Time.zone.now
      usage = find_or_build_license_usage(business)
      usage.update_usage(business, generated_at)
      with_write { usage.save! }
      business.log_license_usage_update(completed: true)
      if run_again?(business)
        BusinessUpdateLicenseUsageJob.perform_later(business_id)
        set_run_again(false, business: business)
        GitHub.logger.info("license usage update scheduled", {
          "gh.business.id": business_id,
          "gh.business.slug": business.slug,
          "gh.license_usage.completed": false,
        })
      end
    rescue ActiveRecord::RecordInvalid => e
      # If multiple jobs are started at nearly the same time, sometimes the second one tries to make a duplicate
      # license_usage record instead of updating the original one. Retry the job if this happens.
      raise RecordAlreadyExists, e.message if e.message.include?("Validation failed: Business has already been taken")
      raise e
    ensure
      # Make sure we clear the lock, including unexpected errors, so we don't get stuck until the TTL deletes the cache key
      set_job_running(false, business: business)
    end
  end

  sig { params(business: Business).returns(::Business::LicenseUsage) }
  def find_or_build_license_usage(business)
    business.license_usage || business.build_license_usage
  end

  private

  sig { returns(GitHub::Restraint) }
  def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end

  sig { params(run_again: T::Boolean, business: Business).returns(T.any(Integer, T::Boolean)) }
  def set_run_again(run_again, business:)
    run_again ? set_cache(run_again_cache_key(business)) : delete_cache(run_again_cache_key(business))
  end

  sig { params(running: T::Boolean, business: Business).returns(T.any(Integer, T::Boolean)) }
  def set_job_running(running, business:)
    running ? set_cache(running_cache_key(business)) : delete_cache(running_cache_key(business))
  end

  sig { params(business: Business).returns(T::Boolean) }
  def run_again?(business)
    key_exist?(run_again_cache_key(business))
  end

  sig { params(business: Business).returns(String) }
  def running_cache_key(business)
    "#{CACHE_KEY_PREFIX}:running:#{business.id}"
  end

  sig { params(business: Business).returns(String) }
  def run_again_cache_key(business)
    "#{CACHE_KEY_PREFIX}:run_again:#{business.id}"
  end

  sig { params(cache_key: String).returns(T::Boolean) }
  def set_cache(cache_key)
    GitHub.job_coordination_redis.set(cache_key, 1, nx: true, ex: CACHE_TTL.to_i)
  end

  sig { params(cache_key: String).returns(Integer) }
  def delete_cache(cache_key)
    GitHub.job_coordination_redis.del(cache_key)
  end

  sig { params(cache_key: String).returns(T::Boolean) }
  def key_exist?(cache_key)
    GitHub.job_coordination_redis.exists(cache_key)
  end
end
