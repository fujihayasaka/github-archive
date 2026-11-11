# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    # Usage: bin/seed billable_entity_personas
    # Usage: bin/seed billable_entity_personas --rbi_disabled_user=true
    # Usage: bin/seed billable_entity_personas --rbi_disabled_organization=true
    class BillableEntityPersonas < Seeds::Runner
      sig { returns(String) }
      def self.help
        <<~HELP
        Creates Users and Organizations in various billing states.

        This is similar to billing_business_personas but for individual users and organizations
        rather than enterprise businesses.

        Seeding:
        - Creates a user with RBI-disabled auto-pay (India-based credit card)
        - Creates an organization with RBI-disabled auto-pay (India-based credit card)
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {
        rbi_disabled_user: true,
        rbi_disabled_organization: true,
        reset: false,
      })
        require_relative "../factory_bot_loader"
        new.run(options)
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def run(options)
        puts "Creating billable entity personas..."
        puts "------"

        if options[:rbi_disabled_user]
          create_rbi_disabled_user(reset: options[:reset])
        end

        if options[:rbi_disabled_organization]
          create_rbi_disabled_organization(reset: options[:reset])
        end

        puts "\n------"
        puts "Done creating billable entity personas!"
      end

      private

      sig { params(reset: T.nilable(T::Boolean)).returns(User) }
      def create_rbi_disabled_user(reset:)
        login = "rbi-disabled-user"
        puts "\nCreating RBI-disabled user: #{login}"

        if reset
          User.find_by(login: login)&.destroy
          ReservedLogin.untombstone!(login)
        end

        user = User.find_by(login: login)
        if user
          puts "- User already exists"
          ensure_rbi_disabled(user)
        else
          # Use the factory that directly sets auto_pay_reasons to include :india_rbi
          # This avoids calling Zuora API which isn't available in development
          user = FactoryBot.create(:user, :verified,
            login: login,
            billing_type: "card",
            customer_account: FactoryBot.build(:disabled_by_india_rbi_customer_account)
          )
          puts "- Created new user with India-based credit card and RBI-disabled auto-pay"
        end

        FactoryBot.create(:billing_plan_subscription, :zuora, user: user, balance_in_cents: 399_00) unless user.plan_subscription
        ensure_manual_dunning_period(user)

        puts "- Login URL: #{login_url_for(user)}"
        user
      end

      sig { params(reset: T.nilable(T::Boolean)).returns(Organization) }
      def create_rbi_disabled_organization(reset:)
        login = "rbi-disabled-org"
        admin = Seeds::Objects::User.monalisa
        puts "\nCreating RBI-disabled organization: #{login}"

        if reset
          Organization.find_by(login: login)&.destroy
          ReservedLogin.untombstone!(login)
        end

        org = Organization.find_by(login: login)
        if org
          puts "- Organization already exists"
          ensure_rbi_disabled(org)
        else
          # Use the factory that directly sets auto_pay_reasons to include :india_rbi
          # This avoids calling Zuora API which isn't available in development
          org = FactoryBot.create(:organization,
            login: login,
            admin: admin,
            plan: :free,
            billing_type: "card",
            customer_account_factory: :disabled_by_india_rbi_customer_account
          )
          Seeds::Objects::Repository.create(owner_name: org.login, repo_name: "repo1", setup_master: true)
          puts "- Created new organization with India-based credit card and RBI-disabled auto-pay"
        end

        FactoryBot.create(:billing_plan_subscription, :zuora, user: org, balance_in_cents: 399_00) unless org.plan_subscription
        ensure_manual_dunning_period(org)

        org
      end

      sig { params(account: T.any(User, Organization)).void }
      def ensure_rbi_disabled(account)
        customer = account.customer
        return unless customer

        if customer.auto_pay_reasons.include?(:india_rbi)
          puts "- Auto-pay already disabled for RBI"
        else
          Billing::AutoPay.disable!(account: account, reason: :india_rbi)
          puts "- Disabled auto-pay due to RBI regulations"
        end
      end

      sig { params(account: T.any(User, Organization)).void }
      def ensure_manual_dunning_period(account)
        if account.manual_dunning_period
          puts "- Manual dunning period already exists"
        else
          Billing::ManualDunningPeriod.create!(user: account)
          puts "- Created manual dunning period (simulates invoice posted webhook)"
        end
      end

      sig { params(user: User).returns(String) }
      def login_url_for(user)
        UrlHelpers.login_url(
          login: user, protocol: GitHub.scheme, host: GitHub.host_name
        )
      end
    end
  end
end
