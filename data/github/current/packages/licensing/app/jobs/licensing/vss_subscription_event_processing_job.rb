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

    # Retry on StandardError up to five times, in case of transient errors like network issues.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, exception|
      event = job.arguments.first
      ActiveRecord::Base.connected_to(role: :writing) do
        event.failed!
      end
      Failbot.report(exception, vss_subscription_event_id: event.id)
      GitHub.logger.error(
        "Unable to perform vss job after retrying multiple times",
        {
          exception: exception,
          "code.namespace": "Licensing::VssSubscriptionEventProcessingJob",
          "code.function": "perform",
          "gh.licensing.vss_subscription_event.id": event.id
        }
      )
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
      if event.parsed_payload.present?
        enterprise_agreement = Licensing::EnterpriseAgreement.find_by(agreement_id: event.enterprise_agreement_number)
      end

      business = Business.find_by(id: enterprise_agreement&.business_id)
      volume = !business&.metered_plan?

      # Ensure we are always working with the most recent event for the subscription.
      events = Licensing::Vss::VssSubscriptionEvent
        .where(subscription_id: event.subscription_id)
        .order(last_modified_date: :desc)
        .to_a

      # Loop across events in reverse chronological order, processing them until we hit
      # a new assignment, an anonymized remove assignment, or a volume remove assignment.
      last_event = T.let(events.shift, T.nilable(Licensing::Vss::VssSubscriptionEvent))
      found = T.let(false, T::Boolean)
      while last_event.present? && !found

        raise InvalidEventError.new("Invalid JSON in most recent payload") if !last_event.valid_payload?

        with_lock!(last_event.subscription_id) do
          with_write do
            if last_event.new_assignment?
              create_assignment(last_event)
              found = true
            elsif last_event.remove_assignment? && (last_event.anonymized? || (volume && FeatureFlag.vexi.enabled?(:allow_revoke_for_volume, default: false)))
              revoke_assignment(last_event)
              found = true
            end
          end
        end
        last_event = events.shift
      end
      with_write { event.processed! }
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
    end

    sig { params(event: ::Licensing::Vss::VssSubscriptionEvent).void }
    def create_assignment(event)
      # can't create a bundled license assignment without an enterprise agreement number, no business to associate
      return event.processed! if event.enterprise_agreement_number.nil?

      # Don't make a new BundledLicenseAssignment if there is already a non-revoked one for the same subscription, email, and enterprise agreement.
      return event.processed! if Licensing::BundledLicenseAssignment
        .nonrevoked
        .with_subscription(event.subscription_id)
        .where(email: event.email)
        .for_enterprise_agreement(event.enterprise_agreement_number)
        .any?

      enterprise_agreement = Licensing::EnterpriseAgreement.find_by(agreement_id: event.enterprise_agreement_number)
      business = Business.find_by(id: enterprise_agreement&.business_id)

      assignment = Licensing::BundledLicenseAssignment.new(
        enterprise_agreement_number: event.enterprise_agreement_number,
        business_id: enterprise_agreement&.business_id,
        email: event.email,
        identity: event.identity,
        subscription_id: event.subscription_id,
        revoked: false
      )

      # If there is a previous assignment for the same subscription, pull the existing user_id and manual match status forward.
      # This will prevent a user from being billed for in the event the replacement user does not match, in which case we need to preserve the previously matched user.
      previous_assignment = Licensing::BundledLicenseAssignment.assigned_user.with_subscription(event.subscription_id).nonrevoked.last
      assignment.user_id = previous_assignment&.user_id
      assignment.manual_match = previous_assignment&.manual_match || false
      assignment.manual_match_at = previous_assignment&.manual_match_at

      Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).nonrevoked.each do |assignment|
        assignment.revoke!
      end

      # This sets the user_id based on the email, if available, so we don't save it once without a user ID, and then
      # again with a user ID via the job, which would trigger two hydro events in rapid succession.
      assignment.set_user_by_verified_emails

      # Save after handling potential missing revoke so callbacks are able to assign a new user.
      assignment.save!

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

      assignment = if business.present?
        Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).where(email: event.email).last
      else
        Licensing::BundledLicenseAssignment.with_subscription(event.subscription_id).last
      end

      return event.processed! if assignment.nil? || assignment.revoked?

      assignment.revoke!(email: event.email)
    end
  end
end
