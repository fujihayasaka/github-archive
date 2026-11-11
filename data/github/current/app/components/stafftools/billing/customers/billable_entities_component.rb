# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class BillableEntitiesComponent < ApplicationComponent

        sig { params(customer: Customer, customer_accounts: T.untyped, billable_owner: T.untyped).void }
        def initialize(customer:, customer_accounts:, billable_owner:)
          @customer = customer
          @customer_accounts = customer_accounts
          @billable_owner = billable_owner
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T.untyped) }
        attr_reader :customer_accounts

        sig { returns(T.untyped) }
        attr_reader :billable_owner

        sig { returns(T.nilable(Business)) }
        def business
          customer.business
        end

        sig { returns(T::Array[T.untyped]) }
        def delegated_organizations
          return [] unless business.present?

          T.must(business).organizations.to_a
        end

        sig { returns(T::Array[CustomerAccount]) }
        def organizations
          customer_accounts.select { |ca| ca.user&.organization? }
        end

        sig { returns(T::Array[CustomerAccount]) }
        def users
          customer_accounts.reject { |ca| ca.user&.organization? }
        end

        sig { params(account: CustomerAccount).returns(String) }
        def entity_icon(account)
          if account.user&.organization?
            "organization"
          else
            "person"
          end
        end

        sig { params(account: CustomerAccount).returns(String) }
        def entity_type_label(account)
          if account.user&.organization?
            "Organization"
          else
            "User"
          end
        end

        sig { params(account: CustomerAccount).returns(Symbol) }
        def verification_scheme(account)
          account.verified? ? :success : :attention
        end

        sig { params(account: CustomerAccount).returns(String) }
        def verification_text(account)
          account.verified? ? "Verified" : "Unverified"
        end
      end
    end
  end
end
