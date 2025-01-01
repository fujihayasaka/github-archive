# typed: strict
# frozen_string_literal: true

require "monolith-twirp-billing-accounts"

module Api::Internal::Twirp::Billing
  module Accounts
    module V1
      # Handler for the MonolithTwirp::Billing::Accounts::V1::BillableOwnerAPIService
      class BillableOwnerAPIHandler < Api::Internal::Twirp::Handler

        include Scientist

        allow_access_for :client, allowed_clients: ["billing"]
        handles_service MonolithTwirp::Billing::Accounts::V1::BillableOwnerAPIService

        # Public: Implementation of the ResolveBillableOwner Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Billing::Accounts::V1::ResolveBillableOwnerRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Billing::Accounts::V1::ResolveBillableOwnerResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Billing::Accounts::V1::ResolveBillableOwnerRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(T::Hash[T.untyped, T.untyped], Twirp::Error))
        end
        def resolve_billable_owner(req, env)
          if req.account_id.zero? && req.customer_id.zero?
            return Twirp::Error.invalid_argument("must have either an account_id or customer_id")
          end

          # If we have a customer ID without an account ID, then usage should be tied to a business and we won't need
          # to fetch owner info. Otherwise, we use the account ID to find the owner to later query budget info.
          if req.account_id.nonzero?
            owner = case req.account_type
            when :ACCOUNT_TYPE_BUSINESS
              Business.find_by(id: req.account_id)
            when :ACCOUNT_TYPE_USER
              User.find_by(id: req.account_id)
            else
              return Twirp::Error.invalid_argument("must be a valid AccountType", arguments: "account_type")
            end

            return Twirp::Error.not_found("Owner '#{req.account_id}' (#{req.account_type}) was not found") unless owner
          end

          if req.customer_id.zero?
            owner = T.must(owner)
            billable_owner = owner.delegate_billing_to_business? ? T.cast(owner, User).business : owner
            customer = fetch_or_create_customer(billable_owner)
          else
            customer = Customer.find_by(id: req.customer_id)
            return Twirp::Error.not_found("Customer '#{req.customer_id}' was not found") unless customer

            billable_owner = customer.billable_owner
            if billable_owner.nil?
              return Twirp::Error.not_found("Billable owner for Customer '#{req.customer_id}' was not found")
            end
          end

          plan_subscription = scientist_plan_subscription(billable_owner, customer)

          has_active_enterprise_agreements = false
          if billable_owner.is_a?(Business)
            has_active_enterprise_agreements = billable_owner.enterprise_agreements.active.any?
          end

          {
            billable_owner_type: account_type_for(billable_owner),
            billable_owner_id: billable_owner.id,
            zuora_account_number: customer.zuora_account_number,
            zuora_subscription_number: plan_subscription&.zuora_subscription_number,
            zuora_charge_number: plan_subscription&.zuora_rate_plan_charge_number(
              product_rate_plan_charge_id: zuora_product_rate_plan_charge_id_for(billable_owner: billable_owner, zuora_product_rate_plan_charges: req.zuora_product_rate_plan_charges).to_s,
            ),
            azure_subscription_id: customer.azure_subscription_id,
            bill_cycle_day: billable_owner.metered_cycle_day,
            budgets: budgets_for(owner: owner, billable_owner: billable_owner, budget_group: req.budget_group),
            entitlement: entitlement_for(billable_owner: billable_owner, product_name: req.product_name),
            is_metered_through_azure: has_active_enterprise_agreements || customer.metered_via_azure || false,
            is_free_usage_user: plan_subscription&.has_free_usage_product? || false,
            entitlement_plan_name: billable_owner.plan.entitlement_plan_name,
            customer_id: customer.id
          }
        end

        private

        sig { params(billable_owner: ::Billing::Types::Account, customer: Customer).returns(T.nilable(T.any(::Billing::PlanSubscription, ::Billing::SalesServePlanSubscription))) }
        def scientist_plan_subscription(billable_owner, customer)
          Scientist.run "billing.dotcom.resolve_plan_subscription" do |e|
            e.context({
              customer_id: customer.id,
              billable_owner_id: billable_owner.id,
              billable_owner_type: billable_owner.is_a?(Business) ? "business" : "user"
            })

            e.use { billable_owner.active_plan_subscription }
            e.try { customer.active_plan_subscription }
          end
        end

        sig { params(account: ::Billing::Types::Account).returns(Symbol) }
        def account_type_for(account)
          case account
          when Business
            :ACCOUNT_TYPE_BUSINESS
          when User
            :ACCOUNT_TYPE_USER
          end
        end

        sig { params(billable_owner: ::Billing::Types::Account).returns(Customer) }
        def fetch_or_create_customer(billable_owner)
          customer = T.let(billable_owner.customer, T.nilable(Customer))

          return customer if customer

          ActiveRecord::Base.connected_to(role: :writing) do
            customer = Billing::CreateCustomer.perform(billable_owner).customer

            GitHub.dogstats.increment(
              "billing.resolve_billable_owner.create_customer.count",
              tags: ["success:#{customer.present?}"],
            )

            customer
          end
        end

        sig { params(billable_owner: ::Billing::Types::Account, zuora_product_rate_plan_charges: T.untyped).returns(T.nilable(String)) }
        def zuora_product_rate_plan_charge_id_for(billable_owner:, zuora_product_rate_plan_charges:)
          if billable_owner.invoiced?
            zuora_product_rate_plan_charges&.sales_serve_id
          else
            zuora_product_rate_plan_charges&.self_serve_id
          end
        end

        sig { params(billable_owner: ::Billing::Types::Account, budget_group: String, owner: T.nilable(::Billing::Types::Account)).returns(T::Array[T::Hash[String, T.untyped]]) }
        def budgets_for(billable_owner:, budget_group:, owner: nil)
          budgets = budgets_list(owner: owner, billable_owner: billable_owner, budget_group: budget_group)
          budgets.map do |budget|
            budget.attributes.slice(
              "enforce_spending_limit",
              "spending_limit_in_subunits",
              "spending_limit_currency_code",
            ).merge("budget_id" => budget.id)
          end
        end

        sig { params(owner: T.nilable(::Billing::Types::Account), billable_owner: ::Billing::Types::Account, budget_group: String).returns(T::Array[Billing::Budget]) }
        def budgets_list(owner:, billable_owner:, budget_group:)
          return [billable_owner.budgets.new(enforce_spending_limit: false)] if budget_group.to_s.downcase == Billing::Budget::NO_BUDGET.to_s
          return [billable_owner.budgets.new] if Billing::Budget.products.exclude?(budget_group)

          billable_owner_budget = billable_owner.budget_for(group: budget_group)
          return [billable_owner_budget] unless GitHub.flipper[:ghe_spending_limits].enabled?(billable_owner)
          return [billable_owner_budget] if owner.nil?

          owner_budget = owner.budget_for(group: budget_group)
          return [owner_budget] if owner == billable_owner

          budgets = [billable_owner_budget]
          budgets << owner_budget if owner_budget.persisted?
          budgets
        end

        sig { params(billable_owner: ::Billing::Types::Account, product_name: String).returns({ quantity: Billing::Types::NonMoneyNumeric }) }
        def entitlement_for(billable_owner:, product_name:)
          case product_name
          when "actions"
            {
              quantity: billable_owner.plan.actions_included_private_minutes,
            }
          when "packages"
            {
              quantity: billable_owner.plan.package_registry_included_bandwidth * 1.gigabyte,
            }
          when "shared_storage"
            calculator = Billing::MeteredBilling::HourlyRateCalculator.new
            {
              quantity: calculator.hourly_rate_for(units_per_month: billable_owner.plan.shared_storage_included_megabytes) * 1.megabyte,
            }
          else
            {
              quantity: 0,
            }
          end
        end
      end
    end
  end
end
