# typed: strict
# frozen_string_literal: true

module Licensing
  class VssSubscriptionEventProcessingJob < ApplicationJob

    retry_on_dirty_exit

    InvalidEventError = Class.new(StandardError)

    retry_on GitHub::Restraint::UnableToLock do |job, _error|
      GitHub.dogstats.increment("licensing.vss_subscription_event_processing_job.terminally_unable_to_lock")
      GitHub.logger.info(
        "Unable to obtain lock after retrying multiple times - discarding",
        "code.namespace" => "Licensing::VssSubscriptionEventProcessingJob",
        "code.function" => "process",
        "gh.licensing.vss_subscription_event.id" => job.arguments.first.id
      )
    end

    retry_on Audit::EventForwarder::SubscribeError do |_job, error|
      Failbot.report(error)
    end

    # Retry deserialization errors in case it's a race condition where the job is running before the
    # transaction that creates the event is committed.
    retry_on ActiveJob::DeserializationError

    retry_on(ActiveRecord::ConnectionFailed, wait: :polynomially_longer, attempts: 3) do |_job, error|
      Failbot.report(error)
    end

    queue_as :licensing

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def perform(event)
      parsed_event = ::Licensing::Vss::ParsedSubscriptionEvent.new(event.payload)

      raise InvalidEventError.new("Invalid JSON") if !parsed_event.valid?

      with_lock!(parsed_event.subscription_id) do
        with_write do
          if parsed_event.new_assignment?
            create_assignment(parsed_event: parsed_event, event: event)
          elsif parsed_event.remove_assignment?
            revoke_assignment(parsed_event: parsed_event, event: event)
          else
            event.processed!
          end
        end
      end
    rescue InvalidEventError => ex
      Failbot.report(ex, vss_subscription_event_id: event.id)
      with_write { event.failed! }
    rescue GitHub::Restraint::UnableToLock
      GitHub.dogstats.increment("licensing.vss_subscription_event_processing_job.unable_to_lock")
      GitHub.logger.info(
        "Unable to obtain lock for subscription ID",
        "code.namespace" => "Licensing::VssSubscriptionEventProcessingJob",
        "code.function" => "process",
        "gh.licensing.vss_subscription_event.subscription_id" => T.must(parsed_event).subscription_id
      )
      raise
    rescue StandardError # rubocop:todo Lint/GenericRescue
      with_write { event.failed! }
      raise
    end

    sig { params(parsed_event: ::Licensing::Vss::ParsedSubscriptionEvent, event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def revoke_assignment(parsed_event:, event:)
      assignment = Licensing::BundledLicenseAssignment
        .where(subscription_id: parsed_event.subscription_id).last

      return event.processed! if assignment.nil? || assignment.revoked?

      assignment.revoke!(email: parsed_event.email)

      event.processed!
    end

    sig { params(parsed_event: ::Licensing::Vss::ParsedSubscriptionEvent, event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def create_assignment(parsed_event:, event:)
      return event.processed! if parsed_event.enterprise_agreement_number.nil?
      return event.processed! if Licensing::BundledLicenseAssignment.nonrevoked.where(subscription_id: parsed_event.subscription_id, email: parsed_event.email).any?

      if Licensing::BundledLicenseAssignment.nonrevoked.where(subscription_id: parsed_event.subscription_id).any?
        raise InvalidEventError.new("Non-revoked assignment already exists - events processed out of order?")
      end

      Licensing::BundledLicenseAssignment.create!(
        enterprise_agreement_number: parsed_event.enterprise_agreement_number,
        business_id: Licensing::EnterpriseAgreement.find_by(agreement_id: parsed_event.enterprise_agreement_number)&.business_id,
        email: parsed_event.email,
        subscription_id: parsed_event.subscription_id,
        revoked: false
      )

      event.processed!
    rescue ActiveRecord::RecordInvalid
      raise InvalidEventError.new("Invalid Event")
    end

    sig { params(subscription_id: String, block: T.proc.returns(T.untyped)).void }
    def with_lock!(subscription_id, &block)
      GitHub::Restraint.new.lock!("#{self.class.name}-#{subscription_id}", _n = 1, _ttl = 1.minute) do
        yield
      end
    end
  end
end
