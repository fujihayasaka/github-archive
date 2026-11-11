# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class ZuoraWebhooks < Seeds::Runner
      sig { returns(String) }
      def self.help
        <<~HELP
        Creates Zuora webhooks for testing the stafftools webhooks triage dashboard.

        Options:
          --login LOGIN   Attach webhooks to this user's Zuora account (default: monalisa).
                          A customer with a zuora_account_id will be created if needed.
        HELP
      end

      sig { params(options: T::Hash[T.untyped, T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"

        login = options[:login] || "monalisa"
        user = ::User.find_by_login(login)
        raise "User '#{login}' not found" unless user

        account_id = ensure_zuora_account!(user)
        puts "Using Zuora account #{account_id} for #{user.login}"

        create_webhooks(account_id)
        puts "Created Zuora webhooks for #{user.login} (#{account_id})"
        puts "View them at: /stafftools/users/#{user.login}/billing/zuora_webhooks"
      end

      sig { params(user: ::User).returns(String) }
      def self.ensure_zuora_account!(user)
        unless user.customer_account
          customer_account = FactoryBot.create(:credit_card_customer_account, user: user)
          user.update!(billing_type: "card", customer_account: customer_account)
          user.reset_customer
        end

        customer = T.must(user.customer)
        if customer.zuora_account_id.blank?
          customer.update!(zuora_account_id: SecureRandom.hex)
        end

        customer.zuora_account_id
      end

      sig { params(account_id: String).void }
      def self.create_webhooks(account_id)
        # Pending webhooks — mix of types and ages
        FactoryBot.create(:zuora_webhook, :payment_processed, :pending,
          account_id: account_id, created_at: 6.minutes.ago)
        FactoryBot.create(:zuora_webhook, :amendment_processed, :pending,
          account_id: account_id, created_at: 30.minutes.ago)
        FactoryBot.create(:zuora_webhook, :invoice_posted, :pending,
          account_id: account_id, created_at: 2.hours.ago)

        # Stale webhook (past alert threshold)
        FactoryBot.create(:zuora_webhook, :subscription_created, :pending,
          account_id: account_id, created_at: 4.hours.ago)

        # Investigating webhooks — one with issue link, one without
        FactoryBot.create(:zuora_webhook, :payment_declined, :investigating,
          account_id: account_id, created_at: 1.hour.ago,
          investigation_notes: "Tracking in https://github.com/github/billing/issues/1234")
        FactoryBot.create(:zuora_webhook, :account_updated, :investigating,
          account_id: account_id, created_at: 45.minutes.ago,
          investigation_notes: "Waiting on customer response")

        # Ignored webhook
        FactoryBot.create(:zuora_webhook, :payment_processed, :ignored,
          account_id: account_id, created_at: 3.hours.ago)

        # Processed webhook
        FactoryBot.create(:zuora_webhook, :amendment_processed, :processed,
          account_id: account_id, created_at: 5.hours.ago)
      end
    end
  end
end
