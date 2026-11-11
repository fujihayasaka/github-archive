# typed: true
# frozen_string_literal: true

class HydroSecretScanningAssessmentCompleteProcessorJob < HydroMessageJob
  include SecretScanning::Features::FeatureFlagHelper

  queue_as :hydro_secret_scanning_assessment_complete_processor

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # This job sends emails for completed assessments
  def perform
    ActiveRecord::Base.connected_to(role: :reading) do
      actor = T.let(nil, T.nilable(User))
      owner = T.let(nil, T.nilable(T.any(Organization, Business)))
      owner_scope = T.let(nil, T.nilable(Symbol))

      GitHub::CurrentTenant.unscope do
        if message[:requested_by_id] == 0
          GitHub.logger.error("no requested_by_id in message")
          raise GetOwnerAndUsersToNotifyError.new("no requested_by_id in message")
        end

        actor = User.find_by(id: message[:requested_by_id])
        if !actor.present?
          raise GetOwnerAndUsersToNotifyError.new("cannot find user")
        end
        # Check if the actor is subscribed to email notifications
        return unless Notifications::Settings.watcher_email?(actor)

        owner_scope = message[:owner_scope]
        if owner_scope == :OWNER_SCOPE_ORGANIZATION
          owner = Organization.find_by(id: message[:owner_id])
        elsif owner_scope == :OWNER_SCOPE_BUSINESS
          owner = Business.find_by(id: message[:owner_id])
        end
        if owner.nil?
          raise GetOwnerAndUsersToNotifyError.new("cannot find owner")
        end
      end

      assessment_number = message[:assessment_number]
      num_results = message[:num_secrets_found]

      SecretScanningMailer.assessment_complete_summary(T.must(actor), T.must(owner), T.must(owner_scope), assessment_number, num_results).deliver_later
      GitHub.logger.info("Queued email to notify completion of assessment")

    end
  end

  class GetOwnerAndUsersToNotifyError < StandardError
  end

end
