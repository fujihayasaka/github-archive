# typed: true
# frozen_string_literal: true

module Sponsors
  module Orgs
    module PremiumDashboard
      class CurrentBalanceComponent < ApplicationComponent
        def initialize(org:)
          @org = org
        end

        EMAIL_SUBJECT = "Request for Invoice"
        EMAIL_BODY = "We'd like to top up our balance, please send us a new order form."
        DATE_FORMAT = "%b %e, %Y"

        private

        delegate :calculable?, :zero_balance_date, :remaining_balance, to: :zero_balance_calculator

        attr_reader :org

        def render?
          sponsors_customer.present?
        end

        memoize def current_balance
          sponsors_customer.credit_balance
        end

        def can_calculate_zero_balance_date?
          calculable?
        end

        def any_leftover_balance?
          remaining_balance > 0
        end

        def beginning_of_current_month
          Date.current.beginning_of_month
        end

        def one_year_from_now
          12.months.from_now.end_of_month
        end

        memoize def active_recurring_sponsorships
          @org
            .sponsorships_as_sponsor
            .active
            .recurring
        end

        memoize def zero_balance_calculator
          Sponsors::ZeroBalanceDateCalculator.new(
            sponsorships: active_recurring_sponsorships,
            current_balance: current_balance,
            customer: sponsors_customer
          )
        end

        memoize def sponsors_customer
          @org.sponsors_customer
        end

        memoize def latest_invoiced_agreement_signature
          SponsorsInvoicedAgreementSignature
            .for_org(@org)
            .order(created_at: :desc)
            .includes(:agreement)
            .first
        end

        def org_has_signed_agreement?
          latest_invoiced_agreement_signature.present?
        end
      end
    end
  end
end
