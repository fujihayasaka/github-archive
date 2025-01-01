# typed: strict
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class PendingChangeNoticeComponent < ApplicationComponent
      extend T::Sig

      sig { params(sponsorship: Sponsorship).void }
      def initialize(sponsorship:)
        @sponsorship = sponsorship
      end

      private

      sig { returns T::Boolean }
      def render?
        GitHub.sponsors_enabled? && @sponsorship.pending_change.present?
      end

      sig { returns String }
      def change_type
        change_type = pending_change.type
        change_description = case change_type
        when Sponsorship::PendingChange::Type::Cancellation
          "cancellation"
        when Sponsorship::PendingChange::Type::Downgrade
          "downgrade"
        when Sponsorship::PendingChange::Type::Activation
          "activation"
        when Sponsorship::PendingChange::Type::Upgrade
          "upgrade"
        when Sponsorship::PendingChange::Type::NOP
          "change"
        else
          T.absurd(change_type)
        end
      end

      sig { returns String }
      def next_billing_date
        pending_change.active_on.strftime("%B %-d, %Y")
      end

      sig { returns Sponsorship::PendingChange }
      memoize def pending_change
        change = T.cast(@sponsorship.pending_change, T.nilable(Sponsorship::PendingChange))
        T.must_because(change) { "only renders when pending change present" }
      end

      sig { returns Sponsorship }
      attr_reader :sponsorship
    end
  end
end
