# typed: strict
# frozen_string_literal: true

module Billing
  class HelpHubEligibility

    DOGSTATS_ROOT_VALUE = "billing.help_hub_eligibility"

    sig { params(account: Billing::Types::Account).void }
    def initialize(account:)
      @account = account
    end

    # Public: Does this user pay us for lfs, packages, actions, storage, or Codespaces?
    #
    # * Has paid us in the last two months for metered billing products(Actions/packages/codespaces), regardless of refunds OR
    # * Will likely pay us at the end of this cycle based on current usage of metered billing products OR
    # * has paid us for LFS in the last two months (if monthly), or year (if yearly) OR
    # * has at least one LFS data pack currently
    #
    # Returns a Boolean
    #
    # Deprecation: This method no longer works since it relies on usage data from Meuse
    # All customers usage and LFS are not sent to Billing Platform hence every customer
    # is returning false for "eligible_based_on_usage_products?"
    # This is called from HelpHub https://github.com/github/github/blob/3c46db2121c0cdfc4073a4fc182447e6bf4ea9c6/app/api/internal/twirp/support/helphub/v1/users_api_handler.rb#L538
    # Consider updating the implementation to use data from Billing Platform if this is still important
    # Tracking issue https://github.com/github/gitcoin/issues/22149
    sig { returns(T::Boolean) }
    def eligible_based_on_usage_products?
      GitHub.dogstats.time(dogstats_root_value) do
        usage_customer? || lfs_customer?
      end
    end

    # Public: Is this user eligible for an automated individual copilot refund via HelpHub?
    #
    # Returns a Hash of type HelpHubRefundEligibilityResult that can serialize
    # to MonolithTwirp::Support::HelpHub::V1::RefundEligibilityResultItem
    HelpHubRefundEligibilityResult = T.type_alias do
      {
        product: String,
        eligible: T::Boolean,
        ineligibility_reasons: String,
        subscription_item_id: T.nilable(Integer),
      }
    end
    sig { returns(HelpHubRefundEligibilityResult) }
    def helphub_copilot_refund_eligibility
      eligiblity_checker = CopilotRefundEligibilityValidator.new(account, copilot_subscription_item)

      GitHub.dogstats.time("#{dogstats_root_value}.copilot_refund_eligibility") do
        {
          product: "copilot_individual", # This includes Copilot Pro and Copilot Pro Plus
          eligible: eligiblity_checker.eligible?,
          ineligibility_reasons: eligiblity_checker.ineligibility_reasons.join(" "),
          subscription_item_id: eligiblity_checker.copilot_subscription_item&.id,
        }
      end
    end

    # Public: Does this user have any products that are eligible to be canceled or downgraded via HelpHub?
    #
    # Returns an Array of HelpHubDowngradableProduct that can serialize
    # to MonolithTwirp::Support::HelpHub::V1::HelpHubDowngradableProduct
    HelpHubDowngradableProducts = T.type_alias do
      T::Array[{
        type: String,
      }]
    end
    sig { returns(HelpHubDowngradableProducts) }
    def helphub_downgradable_products
      GitHub.dogstats.time("#{dogstats_root_value}.downgradable_products") do
        products = []
        # Currently only supports "copilot_individual" subscription check
        products.push({ type: "copilot_individual" }) if paid_copilot_individual_user?
        products
      end
    end

    private

    sig { returns(Billing::Types::Account) }
    attr_reader :account

    # Internal: Does this org/user pay us for usage based billing products?
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def usage_customer?
      GitHub.dogstats.time("#{dogstats_root_value}.usage_customer_queries") do
        return true if paid_for_usage_billing_products_in_last_two_months?
        return true if metered_billing_customer?

        !!codespaces_customer?
      end
    end

    # Internal: does this org/user pay us for Actions/Packages usage products?
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def metered_billing_customer?
      GitHub.dogstats.time("#{dogstats_root_value}.metered_billing_customer_queries") do
        return false unless account.has_valid_payment_method?(feature_type: :noncommercial) && account.metered_billing_overage_allowed?(group: "shared")
        will_be_billed_at_end_of_period_for_metered_products?
      end
    end

    # Internal: Does this org/user pay us for Codespaces usage products?
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def codespaces_customer?
      GitHub.dogstats.time("#{dogstats_root_value}.codespaces_customer_queries") do
        return false unless account.has_valid_payment_method?(feature_type: :noncommercial) && account.metered_billing_overage_allowed?(group: "codespaces")
        will_be_billed_at_end_of_period_for_codespaces_products?
      end
    end

    # Internal: has this org/user paid for lfs is the last two months (or year,
    # if on a yearly cycle), or will they pay for it at their upcoming billing date.
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def lfs_customer?
      GitHub.dogstats.time("#{dogstats_root_value}.lfs_customer_queries") do
        return true if paid_for_lfs_recently?
        return false unless account.has_valid_payment_method?(feature_type: :noncommercial) && account.external_subscription?

        # Will they likely be charged for it at next billing date?
        GitHub.dogstats.time("#{dogstats_root_value}.external_subscription_lfs_check") do
          account.plan_subscription.external_subscription.data_packs.to_i > 0
        end
      end
    end

    # Internal: has this org/user paid for data_packs within the last 2 months,
    # if monthly, or the last year, if yearly.
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def paid_for_lfs_recently?
      # Lets not give a two year buffer
      GitHub.dogstats.time("#{dogstats_root_value}.recent_lfs_usage") do
        cutoff_date = if account.yearly_plan?
          account.previous_billing_date
        else
          account.previous_billing_date(cycles: 2)
        end

        account.billing_transactions
          .sales
          .settled
          .where("created_at >= ?", cutoff_date)
          .where("asset_packs_total >= ?", 1)
          .exists?
      end
    end

    # Internal: Has this user paid for any usage products in the last two cycles?
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def paid_for_usage_billing_products_in_last_two_months?
      GitHub.dogstats.time("#{dogstats_root_value}.recent_usage") do
        cutoff_date = ::GitHub::Billing.now - 2.months

        account.line_items.joins(:billing_transaction)
          .where("billing_transaction_line_items.created_at >= ?", cutoff_date)
          .merge(::Billing::BillingTransaction.sales.settled)
          .usage
          .where("billing_transaction_line_items.amount_in_cents != 0")
          .exists?
      end
    end

    # Internal: will this account be billed for actions/packages usage at the end of the cycle?
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def will_be_billed_at_end_of_period_for_metered_products?
      GitHub.dogstats.time("#{dogstats_root_value}.current_metered_usage_will_be_billed") do
        shared_usage = ::Billing::BaseUsage.shared_products_usage(account)

        registry_usage = ::Billing::PackageRegistryUsage.product_usage(account, shared_usage: shared_usage)
        will_pay_for_packages = !registry_usage.has_error? && registry_usage.private_gigabytes_used > 0

        shared_storage_usage = ::Billing::SharedStorageUsage.product_usage(account, shared_usage: shared_usage)
        will_pay_for_storage = !shared_storage_usage.has_error? && shared_storage_usage.estimated_monthly_paid_megabytes > 0

        actions_usage = ::Billing::ActionsUsage.product_usage(account, shared_usage: shared_usage)
        will_pay_for_actions = !actions_usage.has_error? && actions_usage.total_paid_minutes_used > 0

        will_pay_for_packages ||
        will_pay_for_storage ||
        will_pay_for_actions
      end
    end

    # Internal: will this account be billed for codespaces usage at the end of the cycle?
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def will_be_billed_at_end_of_period_for_codespaces_products?
      GitHub.dogstats.time("#{dogstats_root_value}.current_codespaces_usage_will_be_billed") do
        ::Billing::Usage::CodespacesCalculator.new(billable_owner: account, owner: account).cost > 0
      end
    end

    # This returns any Copilot subscription item such as Copilot Pro or Copilot Pro Plus
    sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
    def copilot_subscription_item
      @copilot_subscription_item ||= T.let(
        Billing::Public::SubscriptionItem
        .all_active(account:, product: Billing::Public::Product::ProductIdentifier.new(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE))
        .value { [] }
        .first,
        T.nilable(Billing::Public::SubscriptionItem)
      )
    end

    sig { returns(T::Boolean) }
    def paid_copilot_individual_user?
      !!(copilot_subscription_item&.active? && copilot_subscription_item&.paid?)
    end

    sig { returns(String) }
    def dogstats_root_value
      DOGSTATS_ROOT_VALUE
    end

    class CopilotRefundEligibilityValidator
      include ActiveModel::Validations

      sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
      attr_reader :copilot_subscription_item

      sig { returns(T::Array[Billing::Settings::PaymentHistory::PaymentRecord]) }
      attr_reader :payment_records

      sig { returns(Billing::Types::Account) }
      attr_reader :account

      # * Is the account a non-spammy User?
      # * Can we find an active and paid copilot subscription (including under pending change e.g. they've cancelled)?
      # * Has the user not received a refund in the last 100 transactions / 2 years
      # * Will the refunded value be less than ~$100? The answer is yes because of the plan cost but still check
      # * Was the charge in the last 31 days?
      validates :not_a_user, absence: true
      validates :user_flagged, absence: true
      validates :no_eligible_subscriptions_found, absence: true
      validates :recently_refunded, absence: true
      validates :charge_not_found, absence: true
      validates :charge_not_found_under_amount, absence: true
      validates :charge_not_found_after_date, absence: true


      sig { params(account: Billing::Types::Account, copilot_subscription_item: T.nilable(Billing::Public::SubscriptionItem)).void }
      def initialize(account, copilot_subscription_item)
        @account = account
        @copilot_subscription_item = copilot_subscription_item
        @payment_records = T.let(Billing::Settings::PaymentHistory::PaymentRecord.payment_records(target: account, limit: 100), T::Array[Billing::Settings::PaymentHistory::PaymentRecord])
        @last_copilot_charge = T.let(nil, T.nilable(Billing::BillingTransaction::LineItem))
        validate
      end

      sig { returns(T::Array[Symbol]) }
      def ineligibility_reasons
        errors.messages.keys
      end

      sig { returns(T::Boolean) }
      def eligible?
        valid?
      end

      private

      # is the user spammy?
      sig { returns(T::Boolean) }
      def user_flagged
        account.spammy?
      end

      # is the account not a User?
      sig { returns(T::Boolean) }
      def not_a_user
        !account.user?
      end

      # does the customer not have a copilot subscription?
      sig { returns(T::Boolean) }
      def no_eligible_subscriptions_found
        !(copilot_subscription_item&.active? && copilot_subscription_item&.paid?)
      end

      # was the customer refunded for any reason in the last 2 years?
      sig { returns(T::Boolean) }
      def recently_refunded
        payment_records.any? { |t| t.transaction_type == "refund" && t.billing_transaction.updated_at > (Time.now - 2.years) }
      end

      # no copilot charge could be found in the last 100 payment records
      sig { returns(T::Boolean) }
      def charge_not_found
        !last_copilot_charge
      end

      # was the last charge under 120 dollars?
      sig { returns(T::Boolean) }
      def charge_not_found_under_amount
        !!(last_copilot_charge && !last_copilot_charge&.amount_in_cents.between?(1, 120_00))
      end

      # was there no copilot charge in the last year?
      sig { returns(T::Boolean) }
      def charge_not_found_after_date
        !!(last_copilot_charge && last_copilot_charge&.created_at < (Time.now - 1.year))
      end

      # the last succesful copilot charge or nil
      sig { returns(T.nilable(Billing::BillingTransaction::LineItem)) }
      def last_copilot_charge
        @last_copilot_charge ||= T.let(
          payment_records
            .select { |t| t.status == "succeeded" }
            .flat_map { |li| li.billing_transaction.paid_line_items }
            .find { |li| li.copilot? },
          T.nilable(Billing::BillingTransaction::LineItem)
        )
      end
    end
  end
end
