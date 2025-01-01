# typed: true
# frozen_string_literal: true

module Billing

  # Public: A Plain Old Ruby Object (PORO) used for updating a subscription item
  # representing a purchase.
  class UpdateSubscriptionItem

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    include GitHub::Memoizer

    # subscribable - The listing plan or Sponsors tier that was purchased.
    # quantity - How many units of this listing were purchased.
    # plan_subscription - The Billing::PlanSubscription for the account who purchased the item, and that the
    #                              subscription item is associated with.
    # installation_account (optional) - The account to associate the subscription item with.
    # grant_oap (optional) - Whether to grant OAP access to the application.
    # viewer - Current viewer from GraphQL context.
    def self.call(subscribable:, quantity:, plan_subscription:, installation_account: nil, grant_oap: nil, viewer:, is_stafftools_action: false)
      new(subscribable: subscribable, quantity: quantity, plan_subscription: plan_subscription, installation_account: installation_account, grant_oap: grant_oap, viewer: viewer, is_stafftools_action: is_stafftools_action).call
    end

    def initialize(subscribable:, quantity:, plan_subscription:, installation_account: nil, grant_oap: nil, viewer:, is_stafftools_action: false)
      @subscribable = subscribable
      @quantity     = quantity.to_i
      @grant_oap    = grant_oap
      @viewer       = viewer
      @plan_subscription = plan_subscription
      @account = plan_subscription&.billable_entity
      @installation_account = installation_account
      @is_stafftools_action = is_stafftools_action
    end

    sig { returns(Billing::Public::SubscriptionItems::ResultStruct) }
    def call
      if account.blank?
        raise UnprocessableError.new("Account not found")
      end

      unless account.subscription_items_adminable_by?(viewer, subscribable_type: subscribable_type, is_stafftools_action: is_stafftools_action)
        raise ForbiddenError.new("#{viewer} does not have permission to manage this account (#{account})")
      end

      if account.invoiced? && subscribable.paid?
        if subscribable.is_a?(Marketplace::ListingPlan)
          raise UnprocessableError.new("Invoiced customers cannot purchase paid Marketplace plans at this time. " \
            "Please contact support if you have any questions.")
        elsif sponsorship? && !account.sponsors_invoiced?
          raise UnprocessableError.new("Please contact support to sponsor #{subscribable.sponsorable} via invoice.")
        end
      elsif subscribable.paid? && !has_valid_payment_method?
        raise UnprocessableError.new(invalid_payment_method_error_message)
      end

      unless quantity.to_i > 0
        raise UnprocessableError.new("Quantity must be greater than 0.")
      end

      if account.spammy?
        raise UnprocessableError.new("Your account is flagged and unable to make purchases. Please contact support to have your account reviewed.")
      end

      if subscribable.retired?
        raise UnprocessableError.new("Cannot upgrade to a retired plan")
      end

      if grant_oap
        listing = subscribable.listing
        if listing.respond_to?(:listable_is_oauth_application?) && listing.listable_is_oauth_application?
          installation_account.approve_oauth_application(listing.listable, approver: viewer)
        end
      end

      update = ::Billing::SubscriptionItemUpdater.perform(
        subscribable: subscribable,
        quantity: quantity,
        sender: viewer,
        plan_subscription: plan_subscription,
        organization: account.self_serve_payment? ? installation_account : nil
      )

      if update.result.success
        Billing::Public::SubscriptionItems::ResultStruct.new(
          subscription_item: update.subscription_item,
          result: Billing::Public::ResultStruct.new(success: true),
        )
      else
        raise UnprocessableError.new("Could not purchase this item: " + update.result.errors.join(", "))
      end
    end

    private

    attr_reader :grant_oap, :account, :quantity, :subscribable, :viewer, :plan_subscription, :installation_account, :is_stafftools_action

    def invalid_payment_method_error_message
      if sponsorship? && account.has_paypal_account_for_sponsors?
        "GitHub Sponsors no longer accepts PayPal. Update your payment method to continue sponsoring."
      else
        "Please add a payment method before checking out."
      end
    end

    def subscribable_type
      return unless subscribable
      subscribable.class.name
    end

    def has_valid_payment_method?
      if sponsorship?
        account.has_valid_payment_method_for_sponsorships?(feature_type: :noncommercial)
      elsif marketplace? && enterprise_owned_self_serve_org?
        account.has_valid_payment_method?(feature_type: :noncommercial, should_delegate_billing_to_business: true)
      else
        account.has_valid_payment_method?(feature_type: :noncommercial)
      end
    end

    def enterprise_owned_self_serve_org?
      account.organization? && account.business&.self_serve_payment?
    end

    memoize def marketplace?
      subscribable_type == Marketplace::ListingPlan.name
    end

    # Private: Is the subscription item being made for a sponsorship?
    #
    # Returns a Boolean.
    def sponsorship?
      return @is_sponsorship if defined?(@is_sponsorship)
      @is_sponsorship = subscribable_type == "SponsorsTier"
    end
  end
end
