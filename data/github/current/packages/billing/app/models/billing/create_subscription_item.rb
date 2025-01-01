# typed: true
# frozen_string_literal: true

module Billing
  # Public: Common base class for creating a subscription item representing a purchase. Use one of the child classes
  # to actually create a subscription item correctly based on the type of purchase:
  # - Billing::CreateProductSubscriptionItem
  # - Billing::CreateSponsorshipSubscriptionItem
  # - Billing::CreateMarketplaceSubscriptionItem
  class CreateSubscriptionItem

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    include GitHub::Memoizer

    # Required Arguments
    # subscribable - Item being purchased, one of Billing::ProductUUID, SponsorsTier, or Marketplace::ListingPlan
    # quantity     - Integer amount of the subscribable to purchase
    # account      - Billable entity making the purchase, such as a User, Organization, or Business
    # viewer       - User who is making the purchase on behalf of the account; might be the same as the account
    #
    # Optional Arguments
    # organization          - Organization the subscription item should be associated with, if any. Only applies to EA orgs.
    # free_trial_length     - Time duration for how long the free trial should last, if any
    # skip_sync             - When true, skips the plan subscription sync that occurs after subscription item creation
    # is_stafftools_action  - Indicates if the action is being performed by a stafftools user to bypass adminable checks
    # in_app_purchase       - Indicates the subscription was purchased and will be billed via Apple or Google.
    # perform_authorization - When true, creates an authorization prior to creating the subscription item.
    # authorization_amount_in_cents - When provided, creates an authorization for the provided amount instead of using the price of the subscription item.
    #
    sig do
      params(
        subscribable: T.any(Billing::ProductUUID, SponsorsTier, Marketplace::ListingPlan),
        quantity: Integer,
        account: T.nilable(T.any(User, Organization, Business)),
        viewer: User,
        organization: T.nilable(Organization),
        free_trial_length: T.nilable(ActiveSupport::Duration),
        skip_sync: T::Boolean,
        is_stafftools_action: T::Boolean,
        in_app_purchase: T.nilable(Billing::Public::InAppPurchase),
        perform_authorization: T.nilable(T::Boolean),
        authorization_amount_in_cents: T.nilable(Integer),
      ).void
    end
    def initialize(subscribable:, quantity:, account:, viewer:, organization: nil, free_trial_length: nil, skip_sync: false,
      is_stafftools_action: false, in_app_purchase: nil, perform_authorization: false, authorization_amount_in_cents: nil)
      @subscribable = subscribable
      @quantity = quantity.to_i
      @account = account
      @viewer = viewer
      @organization = organization
      @free_trial_length = free_trial_length
      @skip_sync = skip_sync
      @is_stafftools_action = is_stafftools_action
      @in_app_purchase = in_app_purchase
      @perform_authorization = perform_authorization
      @authorization_amount_in_cents = authorization_amount_in_cents
    end

    protected

    attr_reader :account,
      :quantity,
      :subscribable,
      :viewer,
      :organization,
      :free_trial_length,
      :is_stafftools_action,
      :in_app_purchase,
      :perform_authorization,
      :authorization_amount_in_cents

    def call
      validate

      create_authorization if perform_authorization

      # Always skip sync here because we want to do it after any potential plan changes are made
      subscription_item.skip_sync = true

      if save_subscription_item
        after_subscription_item_saved

        { subscription_item: subscription_item }
      else
        errors = subscription_item.errors.full_messages
        errors += plan_subscription.errors.full_messages
        errors += customer.errors.full_messages
        raise UnprocessableError.new("Could not purchase this item: #{errors.join(", ")}")
      end
    end

    # Protected: Called once the subscription item is created. Can be overridden by child classes.
    def after_subscription_item_saved
      account.update_plan_if_addons_changed unless account.is_a?(Business)
      # Next we reload the plan_subscription since the `account.update_plan_if_addons_changed` call
      # above may have changed the plan name on the user's table account which will be used to
      # synchronize the subscription
      plan_subscription&.reload
      update_subscription_item_for_free_trial
      synchronize_plan_subscription unless skip_sync?
    end

    def validate
      validate_account
      validate_adminable_subscription_items
      validate_purchases_allowed
      validate_subscribable_not_retired
      validate_payment_method
      validate_positive_quantity
      validate_in_app_purchase
    end

    def validate_in_app_purchase
      return unless in_app_purchase?

      # We currently only allow users to purchase in-app subscriptions for their user account, not enterprises or orgs.
      unless account.is_a?(User)
        raise UnprocessableError.new("In-app purchases are only available for user accounts.")
      end

      # We only allow monthly IAP subscriptions for now.
      unless subscribable.billing_cycle_month?
        raise UnprocessableError.new("In-app purchases are only available for monthly billing cycles.")
      end

      # IAP subscription trial lengths are controlled by the IAP provider, such as Apple. So for us,
      # let's ensure all consumers acknowledge the trial length is not applicable to our (GitHub) side of things
      # and ensure they pass in 0.days
      if free_trial_length && free_trial_length != 0.days
        raise UnprocessableError.new("In-app purchases do not support free trials within our billing system and are externally controlled via the IAP store(s).")
      end

      case in_app_purchase.type
      when Public::InAppPurchase::Type::Apple
        # Ensure the original_transaction_id is not already tied to a subscription item
        if AppleSubscription.exists?(original_transaction_id: in_app_purchase.identifier)
          raise UnprocessableError.new("Apple subscription already exists for Original Transaction ID.")
        end

        # Original Transaction IDs should be unique across all Apple products/SKU subscriptions.
        # We should never end up where the same transaction ID is already tied to a Pro subcription stored at the
        # Billing::PlanSubscription level, but lets add this check to ensure this assumption is correct.
        if PlanSubscription.exists?(apple_transaction_id: in_app_purchase.identifier)
          raise UnprocessableError.new("Apple subscription for Pro already exists for Original Transaction ID.")
        end
      when Public::InAppPurchase::Type::Google
        # Ensure the purchase token is not already tied to a subscription item
        if GoogleSubscription.exists?(purchase_token: in_app_purchase.identifier)
          raise UnprocessableError.new("Google subscription already exists for purchase token.")
        end
      end
    end

    def validate_account
      raise UnprocessableError.new("Account not found") if account.blank?
    end

    def validate_adminable_subscription_items
      unless account.subscription_items_adminable_by?(viewer, subscribable_type: subscribable_type, is_stafftools_action: is_stafftools_action)
        raise ForbiddenError.new("#{viewer} does not have permission to manage this account (#{account})")
      end
    end

    def validate_purchases_allowed
      result = account.validate_purchases_allowed(actor: viewer, check_trade_restrictions: true)
      raise UnprocessableError.new(result.error_message) if result.failed?
    end

    def validate_subscribable_not_retired
      raise UnprocessableError.new("Cannot subscribe to a retired plan") if subscribable.retired?
    end

    def trial_cancels_on_expiry?
      return false unless free_trial_length
      return false unless subscribable.is_a?(Billing::ProductUUID)
      !subscribable.bill_on_trial_expiration?
    end

    def in_app_purchase?
      in_app_purchase.present?
    end

    def validate_payment_method
      return unless subscribable.paid?
      return if invoiced_account?
      return if trial_cancels_on_expiry?
      return if has_valid_payment_method?
      return if in_app_purchase?

      raise UnprocessableError.new(invalid_payment_method_error_message)
    end

    def invalid_payment_method_error_message
      "Please add a payment method before checking out."
    end

    def validate_positive_quantity
      raise UnprocessableError.new("Quantity must be greater than 0.") unless quantity > 0
    end

    def create_authorization
      amount_in_cents = authorization_amount_in_cents || subscription_item.price.cents
      return if amount_in_cents.zero?
      return unless account.can_be_authorized?(check_overage: false)

      result = Billing::CreateAuthorizationBillingTransactionJob.perform_now(
        entity_id: account.id,
        amount_in_cents: amount_in_cents,
        is_business: account.is_a?(Business),
        origin: self.class.name
      )

      # Explicitly check for false to exclude scenarios where the job raises an exception.
      # In those cases, the job will retry and the account will be locked upon failure.
      raise UnprocessableError.new("A valid payment method is required.") if result == false
    end

    def skip_sync?
      @skip_sync
    end

    memoize def invoiced_account?
      account.invoiced?
    end

    # Protected: May be overridden by child classes. Get the customer to use for creating a new plan subscription, if
    # necessary.
    memoize def existing_customer
      account.customer
    end

    memoize def customer
      # If there wasn't already a billing customer, make a general-purpose one:
      existing_customer || Billing::CreateCustomer.perform(account, actor: viewer).customer
    end

    # Protected: May be overridden by child classes. Get the plan subscription to use for the subscription item.
    memoize def existing_plan_subscription
      account.plan_subscription
    end

    memoize def plan_subscription
      existing_plan_sub = existing_plan_subscription
      return existing_plan_sub if existing_plan_sub

      # Build a new plan subscription to match the purpose of the given customer, e.g., general-purpose
      # or Sponsors-specific, if one doesn't already exist:
      new_plan_sub = Billing::PlanSubscription.new(new_plan_subscription_params)

      unless new_plan_sub.save
        errors = new_plan_sub.errors.full_messages.to_sentence
        raise UnprocessableError.new("Could not save subscription: #{errors}")
      end

      after_plan_subscription_created(new_plan_sub)

      new_plan_sub
    end

    def new_plan_subscription_params
      # Always skip the syncs here because we want to do it after any potential plan changes are made
      if account.is_a?(User)
        { user: account, customer: customer, purpose: customer.purpose, skip_synchronize_later: true }
      else
        { customer: customer, purpose: customer.purpose, skip_synchronize_later: true }
      end
    end

    def after_plan_subscription_created(new_plan_sub)
      # In case the `plan_subscription` relation was already loaded on the account and determined to be nil,
      # reload it now that the record exists:
      account.reload_plan_subscription if new_plan_sub.general_purpose?
    end

    def has_valid_payment_method?
      account.has_valid_payment_method?(feature_type: :noncommercial)
    end

    # Protected: Whether the subscription item being made is using a SponsorsTier, Billing::ProductUUID,
    # or a Marketplace::ListingPlan.
    #
    # Returns a String.
    def subscribable_type
      subscribable.class.name
    end

    memoize def subscription_item
      existing_sub_item = plan_subscription.subscription_items.cancelled.where(subscribable: subscribable).where(organization: organization).first
      if existing_sub_item
        existing_sub_item.quantity = quantity
      end

      (existing_sub_item || new_subscription_item).tap do |sub_item|
        if in_app_purchase?
          case in_app_purchase.type
          when Public::InAppPurchase::Type::Apple
            sub_item.build_apple_subscription(original_transaction_id: in_app_purchase.identifier)
          when Public::InAppPurchase::Type::Google
            sub_item.build_google_subscription(purchase_token: in_app_purchase.identifier)
          end
        end
      end
    end

    def new_subscription_item
      create_settings = { subscribable: subscribable, quantity: quantity, plan_subscription: plan_subscription, organization: organization }

      if free_trial_length && account.eligible_for_free_trial_on?(product: subscribable)
        if GitHub::Billing.future?(GitHub::Billing.today + free_trial_length)
          create_settings[:free_trial_ends_on] = GitHub::Billing.today + free_trial_length
        end
      end

      Billing::SubscriptionItem.new(**create_settings)
    end

    def save_subscription_item
      Billing::SubscriptionItem.transaction do
        before_saving_subscription_item
        subscription_item.save
      end
    end

    # Protected: Called within the transaction just before the subscription item is saved.
    #
    # Returns nothing.
    def before_saving_subscription_item
      # no-op, check child classes for overrides
    end

    def synchronize_plan_subscription
      should_collect_payment_immediately = account.collect_payment_immediately_for_plan_or_seat_changes?\
        && !subscription_item.on_free_trial?\
        && subscription_item.subscribable_Billing_ProductUUID?
      if should_collect_payment_immediately
        CollectPaymentForUpgradeJob.perform_later(
          billable_entity: account,
          old_plan_name: account.plan.name,
          old_seat_count: organization.nil? ? account.seats : organization.seats,
          notify_on_failure: true,
          actor: viewer,
          subscription_item: subscription_item,
          old_subscription_item_quantity: 0,
        )
      else
        plan_subscription.synchronize_later
      end
    end

    def update_subscription_item_for_free_trial
      return unless subscription_item.on_free_trial?

      bill_on_trial_expiration = !subscribable.is_a?(Billing::ProductUUID) || subscribable.bill_on_trial_expiration?

      Billing::SubscriptionItemUpdater.perform(
        subscribable: subscribable,
        organization: organization,
        quantity: bill_on_trial_expiration ? quantity : 0,
        start_free_trial: true,
        sender: viewer,
        plan_subscription: plan_subscription,
        # The synchronization is skipped here because a synchronization will be performed after this call
        skip_sync: true
      )
    end
  end
end
