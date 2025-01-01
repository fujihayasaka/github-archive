# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BillingOrgsVNext < Seeds::Runner
      def self.help
        <<~HELP
        Add organization with billing enabled products
        HELP
      end

      def self.run(options = {})
        require_relative "../factory_bot_loader"

        # create Team organization for testing
        user = Seeds::Objects::User.monalisa
        team_name = "billing-test-org"
        # business plan maps to a "Team" organization
        team_organization = Seeds::Objects::Organization.create(login: team_name, admin: user, plan: "business")

        ::Customer.create(
          billing_type: "invoice",
          billing_end_date: GitHub::Billing.today + 1.year,
          name: team_name,
          billing_attempts: 0,
          term_length: 12,
          billed_via_billing_platform: true,
        )
        team_organization_customer = Customer.find_by(name: team_name)

        if team_organization_customer != nil
          team_organization.customer = team_organization_customer
          team_organization.customer.onboard_to_all_billing_platform_products
        end

        # Create test repo to generate test usage
        Seeds::Objects::Repository.create(
          owner_name: team_name,
          repo_name: "test-repo",
          is_public: false,
          setup_master: true,
          template: true,
        )

        # Create Free organization for testing
        free_name = "billing-test-org-free"
        # business plan maps to a "Team" organization
        free_organization = Seeds::Objects::Organization.create(login: free_name, admin: user, plan: "free")

        ::Customer.create(
          billing_type: "invoice",
          billing_end_date: GitHub::Billing.today + 1.year,
          name: free_name,
          billing_attempts: 0,
          term_length: 12,
          billed_via_billing_platform: true,
        )
        free_organization_customer = Customer.find_by(name: free_name)

        if free_organization_customer != nil
          free_organization.customer = free_organization_customer
          free_organization.customer.onboard_to_all_billing_platform_products
        end

        # Create test repo to generate test usage
        Seeds::Objects::Repository.create(
          owner_name: free_name,
          repo_name: "test-repo",
          is_public: false,
          setup_master: true,
          template: true,
        )

        puts "Done setting up orgs"
      end
    end
  end
end
