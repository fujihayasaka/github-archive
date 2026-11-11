# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BillingSubscriptionItemsStafftools < Seeds::Runner
      LOGIN = T.let("billing-subitems-user", String)

      sig { returns(String) }
      def self.help
        <<~HELP
        Creates a user whose subscription items exercise every state on the
        Stafftools subscription items page (paid, free trial, awaiting payment,
        in-app purchase, refunded, cancelled). Useful for eyeballing the layout.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"

        User.find_by(login: LOGIN)&.destroy if options[:reset]
        ReservedLogin.untombstone!(LOGIN)

        user = Objects::User.create(login: LOGIN)
        unless user.customer_account
          user.update!(billing_type: "card", customer_account: FactoryBot.create(:credit_card_customer_account, user: user))
        end
        user.update!(billed_on: 10.days.from_now.to_date)
        plan_subscription = user.plan_subscription || FactoryBot.create(:billing_plan_subscription, :zuora, user: user)

        trial_ended = GitHub::Billing.today - 1.day

        # Active: paid (offers "Cancel and refund" since it's a paid Copilot item)
        paid = FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 1)
        record_transaction(user, paid.subscribable)

        # Active: free trial
        FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot_pro_plus, billing_cycle: :year),
          free_trial_ends_on: GitHub::Billing.today + 1.month,
          quantity: 1)

        # Active: awaiting payment (no transaction recorded)
        FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot_max, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 1)

        # Active: managed by Apple (in-app purchase)
        FactoryBot.create(:billing_subscription_item, :iap,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot_edu, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 1)

        # Cancelled: refunded
        refunded = FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 0)
        record_transaction(user, refunded.subscribable, refunded: true)

        # Cancelled: paid
        cancelled_paid = FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot_pro_plus, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 0)
        record_transaction(user, cancelled_paid.subscribable)

        # Cancelled: payment not recorded (no transaction)
        FactoryBot.create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: FactoryBot.create(:billing_product_uuid, :copilot_max, billing_cycle: :month),
          free_trial_ends_on: trial_ended,
          quantity: 0)

        puts "Created subscription items for @#{user.login}."
        puts "Visit /stafftools/users/#{user.login}/subscription_items"
      end

      sig { params(user: User, subscribable: ::Billing::ProductUUID, refunded: T::Boolean).void }
      def self.record_transaction(user, subscribable, refunded: false)
        transaction = if refunded
          FactoryBot.create(:billing_transaction, :refunded_sale, user: user)
        else
          FactoryBot.create(:billing_transaction, user: user)
        end
        FactoryBot.create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: subscribable,
          listing: nil,
          service_start_date: GitHub::Billing.today - 1.month,
          service_end_date: GitHub::Billing.today)
      end
    end
  end
end
