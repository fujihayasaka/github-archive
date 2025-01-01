# typed: strict
# frozen_string_literal: true

module Licensing
  class VssSubscriptionEventProcessingJob < ApplicationJob

    retry_on_dirty_exit

    InvalidEventError = Class.new(StandardError)
    NonRevokedAssignmentExistsError = Class.new(StandardError)

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

    # Retry on NonRevokedAssignmentExistsError up to five times, in case the events are processed out of order.
    retry_on NonRevokedAssignmentExistsError, wait: :polynomially_longer, attempts: 5 do |job, error|
      Failbot.report(error)
      event = job.arguments.first
      ActiveRecord::Base.connected_to(role: :writing) do
        event.failed!
      end
    end

    queue_as :licensing

    sig { params(subscription_id: String, block: T.proc.returns(T.untyped)).void }
    def with_lock!(subscription_id, &block)
      GitHub::Restraint.new.lock!("#{self.class.name}-#{subscription_id}", _n = 1, _ttl = 1.minute) do
        yield
      end
    end

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def perform(event)
      raise InvalidEventError.new("Invalid JSON") if !event.valid_payload?

      with_lock!(event.subscription_id) do
        with_write do
          if event.new_assignment?
            create_assignment(event)
          elsif event.remove_assignment?
            revoke_assignment(event)
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
        "gh.licensing.vss_subscription_event.subscription_id" => event.subscription_id
      )
      raise
    rescue NonRevokedAssignmentExistsError
      # This will be handled by the retry_on block above
      raise
    rescue StandardError # rubocop:todo Lint/GenericRescue
      with_write { event.failed! }
      raise
    end

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def create_assignment(event)
      # can't create a bundled license assignment without an enterprise agreement number, no business to associate
      return event.processed! if event.enterprise_agreement_number.nil?

      enterprise_agreement = Licensing::EnterpriseAgreement.find_by(agreement_id: event.enterprise_agreement_number)
      business = Business.find_by(id: enterprise_agreement&.business_id)

      # If there is a non-revoked assignment for the same subscription and email, we do not create a new one.
      return event.processed! if Licensing::BundledLicenseAssignment
        .nonrevoked
        .with_subscription(event.subscription_id)
        .where(email: event.email)
        .any?

      if business.present? && business.feature_enabled?(:vss_handle_missing_remove)
        # handle back-to-back events where the remove event is missing
        handle_missing_remove(event.subscription_id)
      end

      # TODO: remove once `handle_missing_remove` has been validated in production
      if Licensing::BundledLicenseAssignment.nonrevoked.with_subscription(event.subscription_id).any?
        raise NonRevokedAssignmentExistsError.new("Non-revoked assignment already exists - events processed out of order?")
      end

      Licensing::BundledLicenseAssignment.create!(
        enterprise_agreement_number: event.enterprise_agreement_number,
        business_id: enterprise_agreement&.business_id,
        email: event.email,
        identity: event.identity,
        subscription_id: event.subscription_id,
        revoked: false
      )

      event.processed!
    rescue ActiveRecord::RecordInvalid
      raise InvalidEventError.new("Invalid Event")
    end

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def revoke_assignment(event)
      if event.anonymized?
        handle_anonymized_revoke(event)
      else
        handle_revoke(event)
      end

      event.processed!
    end

    private

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def handle_anonymized_revoke(event)
      assignment = Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).last

      return event.processed! if assignment.nil? || assignment.revoked?

      assignment.revoke_anonymized!(email: event.email)
    end

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def handle_revoke(event)
      enterprise_agreement = Licensing::EnterpriseAgreement.find_by(agreement_id: event.enterprise_agreement_number)
      business = Business.find_by(id: enterprise_agreement&.business_id)

      assignment = if business.present? && business.feature_enabled?(:vss_handle_missing_remove)
        Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).where(email: event.email).last
      else
        Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).last
      end

      return event.processed! if assignment.nil? || assignment.revoked?

      assignment.revoke!(email: event.email)
    end

    sig { params(subscription_id: String).void }
    def handle_missing_remove(subscription_id)
      return unless previous_event = ::Licensing::Vss::VssSubscriptionEvent
        .where(subscription_id: subscription_id)
        .order(last_modified_date: :desc)
        .second

      raise InvalidEventError.new("Invalid JSON with parsed payload") if !previous_event.valid?

      if previous_event.new_assignment?
        revoke_assignment(previous_event)
        GitHub.dogstats.increment("licensing.vss_subscription_event_handle_back_to_back_assignment")
        GitHub.logger.info(
          "Successfully handled back-to-back assignment event",
          "code.namespace" => "Licensing::VssSubscriptionEventProcessingJob",
          "code.function" => "handle_missing_remove",
          "gh.licensing.vss_subscription_event.id" => previous_event.id
        )
      end
    end
  end
end
