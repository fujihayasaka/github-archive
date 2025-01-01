# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module AuthAndCapture
    class CheckTrialsForScheduledAuthorizationJob < BillingJob
      queue_as :authorize_ghec_trials
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      AUTHORIZATION_CHECK_DAYS = T.let([2, 15].freeze, T::Array[Integer])

      schedule interval: 6.hours, condition: -> { !GitHub.single_business_environment? }


      sig { void }
      def perform
        trials_to_authorize.each do |trial|
          next if trial.digital_front_door_authorization_sent?
          next unless trial.digital_front_door?
          next if ::Copilot::Business.new(trial).has_staff_created_trial_organization?  # Copilot Business trials created by staff are exempt from payment authorization checks

          result = trial.run_trial_authorization

          if result
            GlobalInstrumenter.instrument(
              "billing.authorize_ghec_trial", {
                enterprise: trial,
                authorization_successful: true,
                expiration_date: trial.trial_expires_at,
              }
            )
            with_write { trial.digital_front_door_authorization! }
          else
            GlobalInstrumenter.instrument(
              "billing.authorize_ghec_trial", {
                enterprise: trial,
                authorization_successful: false,
                expiration_date: trial.trial_expires_at,
              }
            )
            with_write { ::Copilot::Business.new(trial).cancel_copilot_business_trials(User.ghost) }
          end
        end
      end

      private

      sig { returns(T::Array[T::Range[T.untyped]]) }
      def authorization_date_ranges
        AUTHORIZATION_CHECK_DAYS.map do |days|
          days.days&.ago.beginning_of_day..days.days&.ago.end_of_day
        end
      end

      sig { returns(ActiveRecord::Relation) }
      def trials_to_authorize
        Business.trial_active.where(created_at: [authorization_date_ranges])
      end
    end
  end
end
