# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module StripeWebhook
    class AccountUpdated
      sig { returns(::Stripe::Event) }
      attr_reader :event
      sig { returns(Billing::StripeWebhook) }
      attr_reader :webhook

      # Public: Handle the account updated webhook payload
      #
      # webhook - The Billing::StripeWebhook to process
      #
      # Returns nothing
      sig { params(webhook: Billing::StripeWebhook).void }
      def self.perform(webhook)
        new(webhook).perform
      end

      # Public: Initializes a new AccountUpdated webhook handler
      #
      # webhook - The Billing::StripeWebhook to process
      sig { params(webhook: Billing::StripeWebhook).void }
      def initialize(webhook)
        @webhook = webhook
        @event = T.let(webhook.stripe_event, ::Stripe::Event)
        @account_details = T.let(T.cast(@event.data.object, ::Stripe::Account), ::Stripe::Account)
      end

      # Public: Handle the account updated webhook payload
      #
      sig { void }
      def perform
        return unless stripe_connect_account
        Sponsors::SyncStripeAccountDetails.call(
          T.must(stripe_connect_account),
          account_details: account_details
        )
      end

      private

      sig { returns(::Stripe::Account) }
      attr_accessor :account_details

      sig { returns(T.nilable(Billing::StripeConnect::Account)) }
      def stripe_connect_account
        return @stripe_connect_account if defined?(@stripe_connect_account)
        @stripe_connect_account = T.let(
          Billing::StripeConnect::Account.including_deleted.find_by(stripe_account_id: account_details.id),
          T.nilable(Billing::StripeConnect::Account)
        )
      end
    end
  end
end
