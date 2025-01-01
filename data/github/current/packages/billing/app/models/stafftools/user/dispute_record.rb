# typed: strict
# frozen_string_literal: true

module Stafftools
  module User
    class DisputeRecord
      extend T::Sig

      sig { returns(::Billing::Dispute) }
      attr_reader :billing_dispute

      delegate :amount,
        :billing_transaction,
        :created_at,
        :url,
        :platform,
        :platform_dispute_id,
        :refundable?,
        :response_due_by,
        :response_url,
        :transaction_id,
        to: :billing_dispute

      sig { params(billing_dispute: ::Billing::Dispute).void }
      def initialize(billing_dispute)
        @billing_dispute = billing_dispute
      end

      sig { returns(T.nilable(String)) }
      def dispute_url
        url
      end

      sig { returns(T.nilable(String)) }
      def transaction_url
        billing_transaction.platform_url
      end

      sig { returns(String) }
      def platform_name
        platform.to_s.titleize
      end

      sig { returns(String) }
      def transaction_platform_name
        billing_transaction.platform_name
      end

      sig { returns(String) }
      def short_dispute_id
        platform_dispute_id.last(8)
      end

      sig { returns(String) }
      def short_transaction_id
        transaction_id.last(8).upcase
      end

      sig { returns(String) }
      def reason
        billing_dispute.reason.humanize
      end

      sig { returns(String) }
      def status
        billing_dispute.status.humanize
      end

      sig { returns(T::Boolean) }
      def can_respond?
        return false if response_due_by.nil?

        %w[warning_needs_response needs_response].include?(billing_dispute.status)
      end
    end
  end
end
