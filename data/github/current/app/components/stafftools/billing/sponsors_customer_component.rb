# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsCustomerComponent < ApplicationComponent
      sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      private

      sig { returns GitHubSponsors::Types::Sponsor }
      attr_reader :sponsor

      sig { returns T::Boolean }
      def render?
        GitHub.sponsors_enabled?
      end

      sig { returns T.nilable(Customer) }
      memoize def sponsors_customer
        sponsors_customer = sponsor.sponsors_customer
        sponsors_customer if sponsors_customer&.zuora?
      end

      sig { returns T.nilable(::Billing::Money) }
      memoize def sponsorship_credit_balance
        sponsors_customer&.credit_balance
      end

      sig { returns Stafftools::Billing::AddSponsorsCustomerModalComponent }
      memoize def add_sponsors_customer_modal_component
        Stafftools::Billing::AddSponsorsCustomerModalComponent.new(sponsor: sponsor)
      end

      sig { returns Stafftools::Billing::RemoveSponsorsCustomerModalComponent }
      memoize def remove_sponsors_customer_modal_component
        Stafftools::Billing::RemoveSponsorsCustomerModalComponent.new(sponsor: sponsor)
      end

      sig { returns Stafftools::Billing::SponsorsPaymentRunModalComponent }
      memoize def sponsors_payment_run_modal_component
        Stafftools::Billing::SponsorsPaymentRunModalComponent.new(sponsor: sponsor)
      end

      sig { returns Stafftools::Billing::SponsorsAddCreditBalanceModalComponent }
      memoize def sponsors_add_credit_balance_modal_component
        Stafftools::Billing::SponsorsAddCreditBalanceModalComponent.new(sponsor: sponsor)
      end
    end
  end
end
