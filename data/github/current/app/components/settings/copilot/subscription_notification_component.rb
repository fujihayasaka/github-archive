# typed: strict
# frozen_string_literal: true

module Settings
  module Copilot
    class SubscriptionNotificationComponent < ApplicationComponent
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :days_left_on_trial

      sig { returns(Integer) }
      attr_reader :days_until_next_billing_date

      sig do
        params(
          days_left_on_trial: Integer,
          days_until_next_billing_date: Integer
        ).void
      end
      def initialize(days_left_on_trial, days_until_next_billing_date)
        @days_left_on_trial                        = days_left_on_trial
        @days_until_next_billing_date              = days_until_next_billing_date
      end
    end
  end
end
