# typed: strict
# frozen_string_literal: true

module Billing
  # Public: A Plain Old Ruby Object (PORO) used for creating a subscription item
  # representing a sponsorship purchase.
  class CreateSponsorshipSubscriptionItem < CreateSubscriptionItem
    # inputs - Hash containing attributes to create a sponsorship subscription item
    # inputs[:tier] - The SponsorsTier that was purchased.
    # inputs[:sponsor] - The User or Organization that purchased this.
    # inputs[:viewer] - The currently authenticated User acting on behalf of the sponsor. Might be the same as the
    #                   sponsor.
    # inputs[:skip_sync] - Boolean allowing the normal plan subscription sync that occurs after subscription item
    #                      creation to be skipped.
    # inputs[:via_bulk_sponsorship] - Boolean indicating whether this subscription item is being created along with
    #                                 others via our Bulk Sponsorship tool
    #
    # Returns a Hash on success or raises one of `Billing::CreateSubscriptionItem::UnprocessableError` or
    # `Billing::CreateSubscriptionItem::ForbiddenError`. The Hash will have the following keys:
    #   :subscription_item - The created Billing::SubscriptionItem.
    sig do
      params(
        tier: SponsorsTier,
        sponsor: T.any(User, Organization),
        viewer: User,
        skip_sync: T::Boolean,
        via_bulk_sponsorship: T::Boolean,
        active_on: T.nilable(Date),
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def self.call(tier:, sponsor:, viewer:, skip_sync: false, via_bulk_sponsorship: false, active_on: nil)
      new(tier:, sponsor:, viewer:, skip_sync:, via_bulk_sponsorship:, active_on:).call
    end

    sig { returns T.any(User, Organization) }
    attr_reader :sponsor
    delegate :business, to: :sponsor, allow_nil: true

    sig do
      params(
        tier: SponsorsTier,
        sponsor: T.any(User, Organization),
        viewer: User,
        skip_sync: T::Boolean,
        via_bulk_sponsorship: T::Boolean,
        active_on: T.nilable(Date),
      ).void
    end
    def initialize(tier:, sponsor:, viewer:, skip_sync: false, via_bulk_sponsorship: false, active_on: nil)
      @sponsor = sponsor
      super(
        subscribable: tier,
        quantity: 1,
        account: billable_entity,
        viewer: viewer,
        skip_sync: skip_sync,
        organization: organization,
      )
      @via_bulk_sponsorship = T.let(!!via_bulk_sponsorship, T::Boolean)
      @active_on = active_on
    end

    sig { returns T::Hash[T.untyped, T.untyped] }
    def call
      super
    end

    private

    sig { returns T.nilable(Date) }
    attr_reader :active_on

    # Returns the Account that will be billed for this sponsorship.
    #
    # Typically this is the same User or Organization that is the Sponsor
    # This will be the sponsor's business if the sponsor is a member org of a credit-card enterprise
    sig { returns Billing::Types::Account }
    def billable_entity
      return sponsor unless self_serve_enterprise_sponsorship?

      business
    end

    # Organization the subscription item should be associated with, if any.
    #
    # Only applies to enterprise owned orgs
    sig { returns T.nilable(Organization) }
    def organization
      return T.cast(sponsor, Organization) if self_serve_enterprise_sponsorship?

      nil
    end

    sig { void }
    def validate
      super
      validate_purchase_allowed
      validate_sponsors_purpose_customer
      validate_sufficient_credit_balance
      validate_plan_subscription_for_customer
    end

    sig { void }
    def validate_adminable_subscription_items
      return super unless self_serve_enterprise_sponsorship?

      enterprise_adminable_by_viewer = account.subscription_items_adminable_by?(viewer,
        subscribable_type: subscribable_type,
      )
      org_sponsorships_adminable_by_viewer = T.must(organization).subscription_items_adminable_by?(viewer,
        subscribable_type: subscribable_type
      )

      unless enterprise_adminable_by_viewer || org_sponsorships_adminable_by_viewer
        raise ForbiddenError.new("#{viewer} does not have permission to manage this account (#{account})")
      end
    end

    sig { void }
    def validate_purchase_allowed
      return if account.sponsors_invoiced?

      unless sponsor.has_sponsorships_access?
        raise UnprocessableError.new(sponsorship_not_allowed_error_message)
      end

      if invoiced_account?
        raise UnprocessableError.new(contact_support_to_invoice_error_message)
      end
    end

    sig { void }
    def validate_sponsors_purpose_customer
      if customer&.sponsors_purpose? && !account.organization?
        raise UnprocessableError.new("Only organizations can sponsor from a sponsorship-specific account")
      end
    end

    sig { void }
    def validate_sufficient_credit_balance
      return unless account.sponsors_invoiced?

      price = subscribable.price(sponsor: account, prorated: true)
      unless account.sufficient_invoiced_sponsor_balance?(price)
        raise UnprocessableError.new("This amount exceeds what is in your balance. Contact support to add more funds.")
      end
    end

    sig { void }
    def validate_plan_subscription_for_customer
      return unless existing_customer && existing_plan_subscription
      plan_sub = T.must(existing_plan_subscription)
      customer = T.must(existing_customer)
      return if customer == plan_sub.customer

      unless plan_sub.cancelled_or_non_zuora?
        raise UnprocessableError.new("Subscription (#{plan_sub.purpose_description}) is not on " \
          "the right account (#{customer.purpose_description}), but is still active so a new subscription " \
          "cannot be created on the right account.")
      end
    end

    # Private: Overrides Billing::CreateSubscriptionItem#existing_customer.
    sig { returns T.nilable(Customer) }
    memoize def existing_customer
      account.sponsors_customer || account.customer
    end

    # Private: Overrides Billing::CreateSubscriptionItem#existing_plan_subscription.
    sig { returns T.nilable(Billing::PlanSubscription) }
    memoize def existing_plan_subscription
      # Only one plan subscription per purpose per account, so we don't need to look up the subscription based on
      # a particular customer record.
      account.sponsors_plan_subscription
    end

    # Private: Overrides Billing::CreateSubscriptionItem#plan_subscription.
    sig { returns Billing::PlanSubscription }
    memoize def plan_subscription
      existing_plan_subscription || Billing::CreateSponsorsPlanSubscription.call(account: account)
    end

    # Protected: Called within the transaction just before the subscription item is saved. Overrides
    # Billing::CreateSubscriptionItem#before_saving_subscription_item.
    sig { void }
    def before_saving_subscription_item
      bill_on = active_on
      schedule_sub_item_activation if bill_on.present? && GitHub::Billing.future?(bill_on)

      # HACK HACK HACK we currently support moving the plan subscription under a new customer in order
      # to get around a DB constraint that only supports one plan sub per purpose. When migrating an org
      # with an existing Sponsors-purpose plan subscription to Sponsors-invoicing, we need to move
      # the (empty, though that's not obvious here :-) plan subscription under a Sponsors-purpose customer.
      #
      # See https://github.com/github/github/pull/271574 for details.
      return if customer == plan_subscription.customer
      raise ActiveRecord::Rollback unless plan_subscription.update(customer: customer)
    end

    # Private: Support billing sponsorships at a later date
    sig { void }
    def schedule_sub_item_activation
      subscription_item.quantity = 0
      result = Billing::SchedulePlanChange.run(
        account: account,
        plan_subscription: plan_subscription,
        actor: viewer,
        subscribable: subscription_item.subscribable,
        subscribable_quantity: 1,
        organization: organization,
        active_on: active_on,
      )
      raise ActiveRecord::Rollback unless result.success?
    end

    # Private: Overrides Billing::CreateSubscriptionItem#after_subscription_item_saved.
    sig { void }
    def after_subscription_item_saved
      super
      instrument_sponsorship_added
    end

    # Private: Overrides Billing::CreateSubscriptionItem#has_valid_payment_method?.
    sig { returns(T::Boolean) }
    def has_valid_payment_method?
      account.has_valid_payment_method_for_sponsorships?(feature_type: :noncommercial)
    end

    # Private: Overrides Billing::CreateSubscriptionItem#invalid_payment_method_error_message.
    sig { returns String }
    def invalid_payment_method_error_message
      if account.has_paypal_account_for_sponsors?
        "GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor."
      else
        super
      end
    end

    sig { returns String }
    def contact_support_to_invoice_error_message
      "Please contact support to sponsor #{subscribable.sponsorable} via invoice."
    end

    sig { returns String }
    def sponsorship_not_allowed_error_message
      sponsor_type = sponsor.user? ? "user" : "organization"
      "This #{sponsor_type} does not have permission to create sponsorships. Please contact support."
    end

    sig { void }
    def instrument_sponsorship_added
      GitHub.instrument "sponsorship.added", subscription_item_id: subscription_item.id, sender_id: viewer.id,
        via_bulk_sponsorship: @via_bulk_sponsorship
    end

    # Whether or not this is a sponsorship created by an org in a self-serve enterprise
    #
    # Returns true if:
    #   - the sponsor is an org managed by an enterprise
    #   - that enterprise is self served
    sig { returns T::Boolean }
    memoize def self_serve_enterprise_sponsorship?
      enterprise_managed? && business.self_serve_payment?
    end

    sig { returns T::Boolean }
    memoize def enterprise_managed?
      sponsor.organization? && business.present?
    end
  end
end
