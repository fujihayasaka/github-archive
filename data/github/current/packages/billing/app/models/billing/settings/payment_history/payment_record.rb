# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module PaymentHistory
      class PaymentRecord

        include ActionView::Helpers::TextHelper

        sig { returns(Billing::BillingTransaction) }
        attr_reader :billing_transaction

        delegate :billable_entity,
                  :amount_in_cents,
                  :asset_packs_delta,
                  :asset_packs_total,
                  :platform_url,
                  :last_four,
                  :card_type,
                  :created_at,
                  :old_plan_name,
                  :paypal_email,
                  :paypal?,
                  :plan_name,
                  :sale,
                  :refund_amount_in_cents,
                  :seats_total,
                  :seats_delta,
                  :transaction_id,
                  :transaction_type,
                  :yearly?,
          to: :billing_transaction

        delegate :url_helpers, to: "Rails.application.routes"

        sig { params(billing_transaction: Billing::BillingTransaction).void }
        def initialize(billing_transaction)
          @billing_transaction = billing_transaction
        end

        sig do
          params(
            target: Billing::Types::Account,
            limit: Integer
          ).returns(T::Array[T.any(PaymentRecord, RefundPaymentRecord, FailedPaymentRecord)])
        end
        def self.payment_records(target:, limit: 100)
          billing_transactions = target
            .billing_transactions
            .excluding_no_charges
            .excluding_authorizations
            .includes(:refund, :sale)
            .descending
            .limit(limit)
            .to_a
          return [] if billing_transactions.empty?

          billing_transactions.map do |t|
            klass = if t.voided? || t.is_refund? || t.charged_back?
              RefundPaymentRecord
            elsif t.success?
              PaymentRecord
            else
              FailedPaymentRecord
            end
            klass.new(t)
          end
        end

        sig { returns(T.nilable(GitHub::Plan)) }
        def plan
          GitHub::Plan.find(plan_name, effective_at: billable_entity.plan_effective_at, account: billable_entity)
        end

        sig { returns(T.nilable(GitHub::Plan)) }
        def old_plan
          GitHub::Plan.find(old_plan_name, effective_at: billable_entity.plan_effective_at, account: billable_entity)
        end

        sig { returns(String) }
        def human_plan_name
          plan = self.plan
          name = (plan ? plan.display_name : "").humanize
          name = "#{name} yearly" if yearly?
          name.strip
        end

        sig { returns(T.nilable(T::Boolean)) }
        def per_seat?
          plan = self.plan
          plan && plan.per_seat?
        end

        sig { returns(T.nilable(String)) }
        def added_seats_text
          if added_seats?
            "+ #{pluralize(seats_delta, "seat")} (#{seats_total})"
          end
        end

        sig { returns(T.nilable(T::Boolean)) }
        def added_seats?
          per_seat? && seats_delta > 0
        end

        # Internal: String descriptive text about switch to per seat pricing or nil.
        sig { returns(T.nilable(String)) }
        def switch_to_per_seat_text
          if switched_to_per_seat?
            "Switch to #{human_plan_name} (#{seats_total})"
          end
        end

        # Internal: Boolean if billing_transaction records a switch to per seat pricing.
        sig { returns(T.nilable(T::Boolean)) }
        def switched_to_per_seat?
          old_plan = self.old_plan
          per_seat? && (transaction_type == "prorate-switch-to-seat-charge" || (old_plan && !old_plan.per_seat?))
        end

        sig { returns(String) }
        def amount
          Billing::Money.new(amount_in_cents).format
        end

        sig { returns(String) }
        def refund_amount
          Billing::Money.new(0).format
        end

        sig { returns(String) }
        def formatted_date
          created_at.in_billing_timezone.strftime("%Y-%m-%d")
        end

        sig { returns(String) }
        def status_icon
          "check"
        end

        sig { returns(String) }
        def status
          "succeeded"
        end

        sig { returns(Symbol) }
        def status_level
          :default
        end

        sig { returns(T.nilable(String)) }
        def short_transaction_id
          transaction_id&.last(8)&.upcase
        end

        sig { returns(String) }
        def payer_identifier
          paypal? ? paypal_email : "#{card_type} ending in #{last_four}"
        end

        sig { params(format: T.nilable(T.any(String, Symbol))).returns(String) }
        def url_for_receipt(format: nil)
          options = {}
          if format.present?
            options[:format] = format
          end

          if billable_entity.is_a?(Business)
            url_helpers.business_receipt_path(billable_entity.slug, transaction_id, options)
          elsif billable_entity.is_a?(Organization)
            url_helpers.org_receipt_path(billable_entity.display_login, transaction_id, options)
          else
            url_helpers.receipt_path(transaction_id, options)
          end
        end
      end
    end
  end
end
