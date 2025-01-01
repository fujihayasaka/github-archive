# typed: strict
# frozen_string_literal: true

module Billing
  # Public: A Plain Old Ruby Object (PORO) used for creating a subscription item
  # representing a GitHub purchase that isn't for Marketplace or a sponsorship.
  class CreateProductSubscriptionItem < CreateSubscriptionItem
    # Public: Create a subscription item for a regular GitHub product purchase.
    #
    # inputs - Hash containing attributes to create a subscription item
    # inputs[:product_uuid]          - The Billing::ProductUUID to purchase.
    # inputs[:quantity]              - How many units of this listing were purchased.
    # inputs[:account]               - The account that purchased this, such as a User or Organization.
    # inputs[:viewer]                - Currently authenticated User. Might be the same as the account.
    # inputs[:free_trial_length]     - The length of the free trial, if any.
    # inputs[:skip_sync]             - Boolean allowing the normal plan subscription sync that occurs after subscription item
    #                                  creation to be skipped.
    # inputs[:is_stafftools_action]  - Indicates if the action is being performed by a stafftools user to bypass adminable checks.
    # inputs[:in_app_purchase]       - Pass in to indicate the subscription was purchased via Apple or Google.
    #                                  This will then override billing and sure we do not double bill the customer since
    #                                  billing will be handled externally.
    # inputs[:perform_authorization] - When true, creates an authorization prior to creating the subscription item.
    #                                  Does not create the subscription item if the authorization fails.
    # inputs[:authorization_amount_in_cents] - When provided, creates an authorization for the provided amount
    #                                          instead of using the price of the subscription item.
    #
    # Returns a Hash on success or raises one of `Billing::CreateSubscriptionItem::UnprocessableError` or
    # `Billing::CreateSubscriptionItem::ForbiddenError`. The Hash will have the following keys:
    #   :subscription_item - The created Billing::SubscriptionItem.
    sig { params(inputs: T.untyped).returns({ subscription_item: ::Billing::SubscriptionItem }) }
    def self.call(**inputs)
      new(
        product_uuid: inputs.fetch(:product_uuid),
        quantity: inputs.fetch(:quantity),
        account: inputs.fetch(:account),
        viewer: inputs.fetch(:viewer),
        free_trial_length: inputs[:free_trial_length],
        skip_sync: !!inputs[:skip_sync],
        is_stafftools_action: !!inputs[:is_stafftools_action],
        in_app_purchase: inputs[:in_app_purchase],
        perform_authorization: inputs[:perform_authorization],
        authorization_amount_in_cents: inputs[:authorization_amount_in_cents],
      ).call
    end

    sig do
      params(
        product_uuid: ::Billing::ProductUUID,
        quantity: Integer,
        account: ::Billing::Types::Account,
        viewer: ::User,
        free_trial_length: T.nilable(ActiveSupport::Duration),
        skip_sync: T::Boolean,
        is_stafftools_action: T::Boolean,
        in_app_purchase: T.nilable(Billing::Public::InAppPurchase),
        perform_authorization: T.nilable(T::Boolean),
        authorization_amount_in_cents: T.nilable(Integer),
      ).void
    end
    def initialize(product_uuid:, quantity:, account:, viewer:, free_trial_length: nil, skip_sync: false, is_stafftools_action: false,
      in_app_purchase: nil, perform_authorization: false, authorization_amount_in_cents: nil)
      super(subscribable: product_uuid, quantity: quantity, account: account, viewer: viewer,
        free_trial_length: free_trial_length, skip_sync: skip_sync, is_stafftools_action: is_stafftools_action,
        in_app_purchase: in_app_purchase, perform_authorization: perform_authorization, authorization_amount_in_cents: authorization_amount_in_cents)
    end

    sig { returns({ subscription_item: ::Billing::SubscriptionItem }) }
    def call
      super
    end

    sig { void }
    def after_subscription_item_saved
      super
      instrument_subscription_item_created
    end

    sig { void }
    def instrument_subscription_item_created
      business = account if account.business?

      GitHub.instrument(
        "billing.subscription_item_created",
        business: business,
        business_id: business&.id,
        subscription_item_id: subscription_item.id,
        sender_id: viewer.id,
        product_type: subscribable.product_type,
        billing_cycle: subscribable.billing_cycle,
        quantity: quantity,
        in_app_purchase_vendor: in_app_purchase&.type&.serialize,
        in_app_purchase_identifier: in_app_purchase&.identifier,
        perform_authorization: perform_authorization,
        authorization_amount_in_cents: authorization_amount_in_cents,
      )
    end
  end
end
