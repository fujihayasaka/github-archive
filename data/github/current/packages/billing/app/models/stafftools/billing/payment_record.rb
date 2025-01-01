# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class PaymentRecord
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(::Billing::BillingTransaction) }
      attr_reader :billing_transaction

      sig do
        params(billing_transactions: T::Array[::Billing::BillingTransaction])
          .returns(T::Array[::Stafftools::Billing::PaymentRecord])
      end
      def self.for_billing_transactions(billing_transactions)
        billing_transactions.map { |txn| new(txn) }
      end

      delegate :amount,
               :asset_packs_delta,
               :asset_packs_total,
               :billing_email_address,
               :card_number,
               :card_type,
               :charged_back?,
               :copilot_line_items,
               :created_at,
               :credit_balance_adjustment_transaction?,
               :discount_in_cents,
               :advanced_security_line_items,
               :incomplete?,
               :last_four,
               :last_status,
               :live_user,
               :line_items,
               :marketplace_line_items,
               :multiple_products?,
               :notes,
               :old_plan_name,
               :paid_line_items,
               :paypal_email,
               :paypal?,
               :plan_name,
               :platform_name,
               :platform_url,
               :refund,
               :refundable?,
               :seats_delta,
               :seats_total,
               :short_transaction_id,
               :sponsorship_line_items,
               :success?,
               :transaction_id,
               :transaction_type,
               :usage_charged_line_items,
               :user_login,
               :voided?,
               :was_refunded?,
               :zero_charge?,
               :is_authorization?,
               :pending_status_update?,
        to: :billing_transaction

      sig { params(billing_transaction: ::Billing::BillingTransaction).void }
      def initialize(billing_transaction)
        @billing_transaction = billing_transaction
        line_items.load_target unless line_items.loaded?
      end

      sig { returns(T.nilable(::GitHub::Plan)) }
      def plan
        GitHub::Plan.find(
          plan_name,
          account: live_user,
        )
      end

      sig { returns(T.nilable(::GitHub::Plan)) }
      def old_plan
        GitHub::Plan.find(
          old_plan_name,
          account: live_user,
        )
      end

      sig { returns(String) }
      def plan_info
        case transaction_type
        when "prorate-charge"
          added_seats_text || subscription_item_text || "Upgrade to #{plan_display_name}"
        when "prorate-seat-charge"
          "+ #{seats_delta} #{"seat".pluralize(seats_delta)} (#{seats_total})"
        when "prorate-asset-pack-charge"
          "+ #{asset_packs_delta} data #{"pack".pluralize(asset_packs_delta)} (#{asset_packs_total})"
        when "prorate-switch-to-seat-charge"
          "Switch to #{plan_display_name} (#{seats_total} #{"seat".pluralize(seats_total)})"
        when "job-posting"
          "Job posting"
        else
          if switched_to_per_seat?
            "Switch to per-seat (#{seats_total})"
          elsif multiple_products?
            "Multiple Products"
          elsif sponsorship_line_items.any?
            sponsorship_transaction_text
          elsif copilot_line_items.any?
            "GitHub Copilot"
          elsif advanced_security_line_items.any?
            "GitHub Advanced Security"
          else
            recurring_transaction_text
          end
        end
      end

      sig { returns(T::Array[::Billing::BillingTransaction::LineItem]) }
      memoize def non_fee_sponsorship_line_items
        sponsorship_line_items.reject(&:sponsors_fee?)
      end

      sig { returns(T::Array[String]) }
      memoize def unique_sponsorship_tier_frequencies
        return [] if non_fee_sponsorship_line_items.none?

        # Check whether or not we've eager loaded sponsors tiers to determine how we grab frequencies
        if non_fee_sponsorship_line_items.all? { |li| li.association(:sponsors_tier).loaded? }
          non_fee_sponsorship_line_items.filter_map(&:sponsors_tier).map(&:frequency).uniq
        else
          SponsorsTier.where(id: non_fee_sponsorship_line_items.pluck(:subscribable_id)).distinct.pluck(:frequency)
        end
      end

      sig { returns(T.nilable(String)) }
      memoize def sponsorship_tier_summary
        return if unique_sponsorship_tier_frequencies.empty?

        if unique_sponsorship_tier_frequencies.size == 1
          unique_sponsorship_tier_frequencies.first == "one_time" ? "One-time" : "Recurring"
        else
          "Multiple"
        end
      end

      sig { returns(String) }
      def sponsorship_transaction_text
        [
          sponsorship_tier_summary,
          "sponsorship".pluralize(non_fee_sponsorship_line_items.size),
        ].join(" ")
      end

      sig { returns(T.nilable(String)) }
      def plan_display_name
        plan = self.plan
        (plan ? plan.display_name : plan_name)&.titleize&.strip
      end

      sig { returns(T::Boolean) }
      def per_seat?
        !!plan&.per_seat?
      end

      sig { returns(T.nilable(String)) }
      def added_seats_text
        if added_seats?
          "+ #{seats_delta} #{"seat".pluralize(seats_delta)} (#{seats_total})"
        end
      end

      sig { returns(T.nilable(String)) }
      def subscription_item_text
        if marketplace_line_items.present?
          item = marketplace_line_items.first
          listing_plan = item.subscribable
          if item.listing && listing_plan
            "#{item.listing.name} #{listing_plan.name}"
          else
            "Deleted Marketplace Listing"
          end
        elsif sponsorship_tier_summary.present?
          sponsorship_transaction_text
        elsif copilot_line_items.any?
          "GitHub Copilot"
        elsif advanced_security_line_items.any?
          "GitHub Advanced Security"
        end
      end

      # Internal: Returns plan_info for recurring transaction
      sig { returns(String) }
      def recurring_transaction_text
        text = per_seat? ? "#{seats_total} #{"seat".pluralize(seats_total)}" : plan_display_name

        return text.to_s unless usage_charges?
        "#{text} usage overages"
      end

      sig { returns(T::Boolean) }
      def added_seats?
        per_seat? && seats_delta > 0
      end

      # Internal: Whether transaction contains any usage charges
      sig { returns(T::Boolean) }
      def usage_charges?
        usage_charged_line_items.any?
      end

      # Internal: billing_transaction records a switch to per seat pricing.
      sig { returns(T::Boolean) }
      def switched_to_per_seat?
        old_plan = self.old_plan
        per_seat? && (transaction_type == "prorate-switch-to-seat-charge" || (old_plan && !old_plan.per_seat?))
      end

      # Deprecated: Old school Transaction for this billing_transaction. Only
      # used to show a Stafftools note now.
      sig { returns(T.nilable(Transaction)) }
      memoize def legacy_transaction
        Transaction.find_by(billing_transaction_id: billing_transaction.id)
      end

      sig { params(created_at: Time).returns(String) }
      def formatted_date(created_at = self.created_at)
        created_at.strftime("%Y-%m-%d")
      end

      sig { returns(Time) }
      def refund_at
        refund.created_at
      end

      sig { returns(::Billing::Money) }
      def refund_amount
        ::Billing::Money.new(-refund.amount.cents)
      end

      sig { returns(T::Boolean) }
      def full_refund?
        refund.amount.abs == amount.abs
      end

      sig { returns(String) }
      def payer_identifier
        if paypal?
          paypal_email
        elsif last_four.present?
          str = "ending in #{last_four}"
          card_type ? "#{card_type} #{str}" : str
        else
          "card information not available"
        end
      end

      sig { returns(T::Boolean) }
      def show_receipt_link?
        success? && !charged_back? && !zero_charge? && !is_authorization?
      end

      sig { returns(T.any(T.nilable(T::Boolean), String)) }
      def active_coupon
        discount_in_cents && discount_in_cents > 0 && "#{::Billing::Money.new(discount_in_cents).format} off"
      end

      sig { returns(T.nilable(String)) }
      def status_text
        was_refunded? ? "Refunded" : last_status&.humanize
      end
    end
  end
end
