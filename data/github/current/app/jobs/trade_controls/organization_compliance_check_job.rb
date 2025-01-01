# typed: strict
# frozen_string_literal: true

module TradeControls
  class OrganizationComplianceCheckJob < ApplicationJob

    MAX_ATTEMPTS = 2

    queue_as :trade_controls
    retry_on_dirty_exit

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotUnique,
      Freno::Error, # All things Freno
      *Resiliency::Response::UnavailableExceptions, # Recoverable exceptions
    ].freeze, T::Array[T.class_of(StandardError)])

    RETRYABLE_ERRORS.each do |error|
      retry_on error, wait: :polynomially_longer, attempts: 10 do |_job, error|
        Failbot.report(error)
      end
    end

    retry_on WaitForReplication::DataUnavailable, wait: :polynomially_longer, attempts: :unlimited

    RetryableError = Class.new(RuntimeError)

    retry_on(RetryableError, wait: 15.seconds, attempts: MAX_ATTEMPTS) do |job, _error|
      org_id = job.arguments[0]
      if Organization.find_by(id: org_id).nil?
        Failbot.report(ActiveRecord::RecordNotFound.new("Couldn't find Organization with 'id'=#{org_id} after retry"))
      end
    end

    around_enqueue do |_job, block|
      block.call if GitHub.billing_enabled?
    end

    sig do
      params(
        organization_id: T.nilable(Integer),
        email: T.nilable(String),
        website_url: T.nilable(String),
        reason: T.nilable(Symbol),
        event_source: T.nilable(String),
      ).void
    end
    def perform(organization_id, email: nil, website_url: nil, reason: nil, event_source: nil)
      is_enqueued_job = enqueued_at.present?
      if is_enqueued_job
        start_time = enqueued_at.to_datetime.utc
        time_since_enqueued_ms = (Time.now.utc.to_f - start_time.to_f) * 1000
        tags = ["retries: #{executions}"]
      end

      organization = Organization.find_by(id: organization_id)
      if organization.nil?
        # if after max retries we still can't find the org we report the time
        if executions == MAX_ATTEMPTS && is_enqueued_job
          GitHub.dogstats.distribution(
            "org_compliance_check_job.retry.time_ms",
            time_since_enqueued_ms,
            tags: tags
          )
        end

        user = User.find_by(id: organization_id)
        # A reason why the organization record would not be found is when the user
        # is in the process of being transformed into an Organization. If this is the case
        # then we want to retry this job after a short delay to allow the process to complete.
        if user.present? && Organization.transforming?(user)
          raise RetryableError
        else
          Failbot.report(ActiveRecord::RecordNotFound.new("Couldn't find Organization with 'id'=#{organization_id}"))
        end
      else
        return if organization.trade_controls_restriction.any?

        # if there was ever a retry and now the org exists we report the time
        if executions > 1 && is_enqueued_job
          GitHub.dogstats.distribution(
            "org_compliance_check_job.retry.time_ms",
            time_since_enqueued_ms,
            tags: tags
          )
        end

        compliance = Compliance.for(
          email: email,
          website_url: website_url,
          organization: organization,
          check_billing_managers: reason == :organization_billing_manager,
          check_admin: reason == :organization_admin,
          check_profile_email: reason == :organization_profile_email,
          check_billing_email: reason == :organization_billing_email,
          event_source: event_source
        )

        with_write { compliance.check_and_enforce! }
      end
    end
  end
end
