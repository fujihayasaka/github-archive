# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BillingCustomersStafftools < Seeds::Runner
      sig { returns(String) }
      def self.help
        <<~HELP
        Creates diverse Customer records for testing the Stafftools Billing Customers page.
        Includes users, organizations, and businesses with various billing configurations.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"

        mona = Objects::User.monalisa

        # 1. Individual user with card billing
        puts "Creating user with card billing: billing-cust-user"
        login = "billing-cust-user"
        User.find_by(login: login)&.destroy if options[:reset]
        ReservedLogin.untombstone!(login)
        user = Objects::User.create(login: login)
        Objects::Repository.create(owner_name: user.login, repo_name: "test-repo", setup_master: true)
        unless user.customer_account
          user.update!(billing_type: "card", customer_account: FactoryBot.create(:credit_card_customer_account, user: user))
        end
        user.update!(billed_on: 10.days.from_now.to_date)
        FactoryBot.create(:billing_plan_subscription, :zuora, user: user) unless user.plan_subscription
        puts "  -> Customer ##{user.customer&.id} for @#{user.login}"

        # 2. Organization with card billing
        puts "Creating org with card billing: billing-cust-card-org"
        org = create_org(login: "billing-cust-card-org", billing_type: "card", options: options)
        puts "  -> Customer ##{org.customer&.id} for @#{org.login}"

        # 3. Organization with invoice billing
        puts "Creating org with invoice billing: billing-cust-invoice-org"
        org_inv = create_org(login: "billing-cust-invoice-org", billing_type: "invoice", options: options)
        puts "  -> Customer ##{org_inv.customer&.id} for @#{org_inv.login}"

        # 4. Enterprise with invoice billing
        puts "Creating enterprise with invoice billing: Customer Test Enterprise"
        ent_business = create_ent(
          name: "Customer Test Enterprise",
          org_prefix: "cust-ent-org",
          options: options,
        )
        if (customer = ent_business.customer)
          customer.update(billing_type: Customer::BILLING_TYPE_INVOICE)
        end
        puts "  -> Customer ##{ent_business.customer&.id} for #{ent_business.name} (slug: #{ent_business.slug})"

        # 5. Enterprise self-serve with card
        puts "Creating self-serve enterprise: Customer Test Self-Serve"
        ss_business = create_ent(
          name: "Customer Test Self-Serve",
          org_prefix: "cust-ss-org",
          options: options,
          factory_bot_overrides: [:with_self_serve_payment],
        )
        puts "  -> Customer ##{ss_business.customer&.id} for #{ss_business.name} (slug: #{ss_business.slug})"

        # 6. Locked customer
        puts "Creating locked enterprise: Customer Test Locked"
        locked_business = create_ent(
          name: "Customer Test Locked",
          org_prefix: "cust-locked-org",
          options: options,
          factory_bot_overrides: [:with_self_serve_payment],
        )
        if locked_business.customer
          3.times { locked_business.increment_billing_attempts }
          locked_business.disable!
        end
        puts "  -> Customer ##{locked_business.customer&.id} for #{locked_business.name} (LOCKED)"

        # 7. Customer with no payment method
        puts "Creating enterprise with no payment method: Customer Test No Payment"
        nopay_business = create_ent(
          name: "Customer Test No Payment",
          org_prefix: "cust-nopay-org",
          options: options,
          factory_bot_overrides: [:with_self_serve_payment],
        )
        nopay_business.payment_method&.clear_payment_details(mona)
        puts "  -> Customer ##{nopay_business.customer&.id} for #{nopay_business.name} (no payment method)"

        puts ""
        puts "Done! Created 7 customer personas for Stafftools testing."
        puts "Visit /stafftools/billing/customers to search for them."
      end

      sig { params(login: String, billing_type: String, options: T::Hash[Symbol, T.untyped]).returns(Organization) }
      def self.create_org(login:, billing_type:, options:)
        Organization.find_by(login: login)&.destroy if options[:reset]
        ReservedLogin.untombstone!(login)
        org = Objects::Organization.create(login: login, admin: Objects::User.monalisa, plan: "business")
        Objects::Repository.create(owner_name: org.login, repo_name: "repo1", setup_master: true)
        unless org.customer_account
          customer_account = case billing_type
          when "card" then FactoryBot.create(:credit_card_customer_account, user: org)
          when "invoice" then FactoryBot.create(:no_credit_card_customer_account, user: org)
          else raise Objects::CreateFailed, "billing_type must be 'card' or 'invoice'"
          end
          org.update!(billing_type: billing_type, customer_account: customer_account)
          org.reset_customer
        end
        FactoryBot.create(:billing_plan_subscription, :zuora, user: org) unless org.plan_subscription
        org.update!(billed_on: 10.days.from_now.to_date)
        org
      end

      sig { params(name: String, org_prefix: String, options: T::Hash[Symbol, T.untyped], factory_bot_overrides: T::Array[Symbol]).returns(Business) }
      def self.create_ent(name:, org_prefix:, options:, factory_bot_overrides: [])
        Business.find_by(name: name)&.destroy if options[:reset]
        factory_bot_args = [:business, *factory_bot_overrides, { name: name, owners: [Objects::User.monalisa] }]
        business = Business.find_by(name: name) || FactoryBot.create(*T.unsafe(factory_bot_args))
        login = org_prefix
        Organization.find_by(login: login)&.destroy if options[:reset]
        ReservedLogin.untombstone!(login)
        org = Objects::Organization.create(login: login, admin: Objects::User.monalisa)
        org.update!(business: business)
        Objects::Repository.create(owner_name: org.login, repo_name: "repo1", setup_master: true)
        business
      end
    end
  end
end
