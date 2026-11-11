# typed: true
# frozen_string_literal: true

module Billing
  # Public: A Plain Old Ruby Object (PORO) used for creating a subscription item
  # representing a Marketplace purchase.
  class CreateMarketplaceSubscriptionItem < CreateSubscriptionItem
    # inputs - Hash containing attributes to create a subscription item
    # inputs[:listing_plan] - The Marketplace::ListingPlan that was purchased.
    # inputs[:quantity] - How many units of the Marketplace listing were purchased.
    # inputs[:account] - The account that purchased this, such as a User, Organization, or Business.
    # inputs[:installation_account] (optional) - The organization the app will be installed on. Defaults to the account. Only applies to EA orgs.
    # inputs[:grant_oap] (optional) - Whether to grant OAP access to the application.
    # inputs[:viewer] - Currently authenticated User. Might be the same as the account.
    # inputs[:free_trial_length] - The length of the free trial, if any.
    #
    # Returns a Hash on success or raises one of `Billing::CreateSubscriptionItem::UnprocessableError` or
    # `Billing::CreateSubscriptionItem::ForbiddenError`. The Hash will have the following keys:
    #   :subscription_item - The created Billing::SubscriptionItem.
    def self.call(**inputs)
      new(listing_plan: inputs[:listing_plan],
          quantity: inputs[:quantity],
          account: inputs[:account],
          viewer: inputs[:viewer],
          installation_account: inputs[:installation_account],
          grant_oap: inputs[:grant_oap],
          free_trial_length: inputs[:free_trial_length]).call
    end

    def initialize(listing_plan:, quantity:, account:, viewer:, installation_account: nil, grant_oap: nil, free_trial_length: nil)
      super(
        subscribable: listing_plan,
        quantity: quantity,
        account: account,
        viewer: viewer,
        organization: installation_account,
        free_trial_length: free_trial_length,
      )
      @grant_oap = grant_oap
      @installation_account = installation_account.nil? ? account : installation_account
    end

    def call
      super
    end

    private

    attr_reader :grant_oap, :installation_account

    def validate
      super
      validate_purchase_allowed
      validate_installation_account
    end

    def validate_purchase_allowed
      if subscribable.paid? && invoiced_account?
        raise UnprocessableError.new("Invoiced customers cannot purchase paid Marketplace plans at this time. " \
          "Please contact GitHub Support if you have any questions.")
      end
      unless subscribable.can_subscribe_with_account?(installation_account)
        raise UnprocessableError.new("Could not purchase this item: This plan is for #{subscribable.account_type_text} only, please select a different billing account or plan.")
      end
    end

    def validate_installation_account
      return unless account.business?
      if organization.nil?
        raise UnprocessableError.new("Could not purchase this item: An organization is required to purchase this plan.")
      end

      if organization&.business != account
        raise UnprocessableError.new("#{organization} is not a valid installation account.")
      end
    end

    # Private: Overrides Billing::CreateSubscriptionItem#existing_customer.
    # When the account delegates billing to a business, use the business's customer
    # so that any new PlanSubscription is created on the correct customer record.
    memoize def existing_customer
      account.billable_owner.customer
    end

    # Private: Overrides Billing::CreateSubscriptionItem#customer.
    # When falling back to creating a new customer, ensure it's created on the
    # billable owner (e.g., the business) rather than on the account itself.
    memoize def customer
      existing_customer || Billing::CreateCustomer.perform(account.billable_owner, actor: viewer).customer
    end

    # Private: Overrides Billing::CreateSubscriptionItem#existing_plan_subscription.
    memoize def existing_plan_subscription
      return super unless FeatureFlag.vexi.enabled?(:billing_marketplace_existing_plan_subscription, default: false)

      billable_owner = account.billable_owner
      plan_subscription = billable_owner.plan_subscription
      general_plan_subscriptions = billable_owner.plan_subscriptions.general_purpose
      return plan_subscription unless general_plan_subscriptions.limit(2).count > 1

      if plan_subscription.transfer_marketplace_items_to_correct_plan_subscription
        plan_subscription_for_subscription_item = plan_subscription
      else
        plan_subscription_for_subscription_item = general_plan_subscriptions
          .joins(:subscription_items)
          .merge(Billing::SubscriptionItem.with_marketplace_listing_plans_type)
          .where(subscription_items: { organization_id: installation_account.id })
          .first
      end

      plan_subscription_for_subscription_item || plan_subscription
    end

    # Private: Override Billing::CreateSubscriptionItem#save_subscription_item to grant
    # OAuth application access before the subscription item save transaction is opened.
    # The OAuth approval write targets a different cluster than `subscription_items`,
    # so it must not run inside that transaction.
    def save_subscription_item
      grant_oap_to_installation_account
      super
    end

    def grant_oap_to_installation_account
      return unless grant_oap

      listing = subscribable.listing
      if listing.respond_to?(:listable_is_oauth_application?) && listing.listable_is_oauth_application?
        installation_account.approve_oauth_application(listing.listable, approver: viewer)
      end
    end

    # Private: override called from the base class once the subscription item is created for marketplace-specific finalization.
    def after_subscription_item_saved
      super
      complete_marketplace_order_preview
      handle_subscription_item_integration
      reset_marketplace_pending_installation_notice
      instrument_marketplace_purchase
    end

    memoize def marketplace_order_preview
      viewer.marketplace_order_previews.find_by(marketplace_listing_id: subscribable.marketplace_listing_id)
    end

    def complete_marketplace_order_preview
      return unless marketplace_order_preview

      GitHub.dogstats.increment("marketplace.order_previews.completed",
        tags: ["notified:#{marketplace_order_preview.notification_sent?}"])
      marketplace_order_preview.destroy
    end

    def handle_subscription_item_integration
      return unless subscription_item.listable_is_integration?

      installation = IntegrationInstallation.find_by(target: installation_account, integration: subscription_item.listable)
      return unless installation

      subscription_item.record_marketplace_installation(installed_at: installation.created_at)
      subscription_item.update_integrate_installation(installation)
    end

    def reset_marketplace_pending_installation_notice
      if subscription_item.installed_at.nil?
        Marketplace::PendingInstallations::Notice.new(user_id: viewer.id).reset
      end
    end

    def instrument_marketplace_purchase
      purchase_payload = {
        subscription_item_id: subscription_item.id,
        sender_id: viewer.id,
      }
      if marketplace_order_preview
        purchase_payload.merge!(
          order_preview_viewed_at: marketplace_order_preview.viewed_at,
          order_preview_email_notification_sent_at: marketplace_order_preview.email_notification_sent_at,
        )
      end
      GitHub.instrument "marketplace_purchase.purchased", purchase_payload

      # Hydro instrumentation
      hydro_purchase_payload = {
        subscription_item_id: subscription_item.id,
        sender: viewer,
        account: installation_account,
        marketplace_listing_plan: subscribable,
      }
      if marketplace_order_preview
        hydro_purchase_payload.merge!(
          order_preview_viewed_at: marketplace_order_preview.viewed_at,
          order_preview_email_notification_sent_at: marketplace_order_preview.email_notification_sent_at,
        )
      end
      GlobalInstrumenter.instrument("marketplace.purchase_purchased", hydro_purchase_payload)
    end
  end
end
