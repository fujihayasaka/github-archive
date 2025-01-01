# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class GhasCommitters < Seeds::Runner
      def self.help
        <<~HELP
        Creates a business and organizations with different Advanced Security configurations and committer counts.

        HELP
      end

      def self.run(options = {})
        require_relative "../factory_bot_loader"

        require_relative "../runners/billing_product_uuids"
        Seeds::Runner::BillingProductUUIDs::PRODUCT_TYPES.values.each do |product_type|
          Seeds::Runner::BillingProductUUIDs.execute(product_type: product_type)
        end

        actor = Objects::User.monalisa

        committers = create_committers(login_prefix: "ghas-committer", options: options)

        if GitHub.enterprise?
          puts "Enterprise: creating organization and repos..."
          orgs = 2.times.map do |i|
            login = "ghas-committers-org-#{i}"
            Organization.find_by(login: login)&.destroy if options[:reset]
            ReservedLogin.untombstone!(login)
            org = Objects::Organization.create(login: login, admin: actor)
            org.bulk_add_members(committers)
            org.update!(business: GitHub.global_business)
            org
          end

          GhasCommitters.create_repo(actor:, owner: orgs.first, committers: committers, repo_name: "ghas-committers-1") unless options[:skip_repos]
          GhasCommitters.create_repo(actor:, owner: orgs.first, committers: committers[..1], repo_name: "ghas-committers-2") unless options[:skip_repos]
          GhasCommitters.create_repo(actor:, owner: orgs.second, committers: committers[..1], repo_name: "ghas-committers-2") unless options[:skip_repos]
        else
          puts "Creating sales-serve Advanced Security organization..."
          create_organization(actor:, login: "ghas-sales-serve-org", committers: committers, options: options)
          puts "Creating sales-serve Advanced Security business..."
          create_business(actor:, name: "GHAS Sales Serve Business", org_prefix: "ghas-sales-serve-business-org", committers: committers, options: options, type: :sales_purchased)
          puts "Creating Advanced Security metered business...."
          create_business(actor:, name: "GHAS Metered Business", org_prefix: "ghas-metered-business-org", committers: committers, options: options, type: :metered)
          puts "Creating self-serve Advanced Security business...."
          create_business(actor:, name: "GHAS Self Serve Business", org_prefix: "ghas-self-serve-business-org", committers: committers, options: options, type: :self_serve_purchased)
          puts "Creating self-serve Advanced Security trial business...."
          create_business(actor:, name: "GHAS Self Serve Trial Business", org_prefix: "ghas-self-serve-trial-business-org", committers: committers, options: options, type: :self_serve_trial)
          puts "Creating self-serve Advanced Security trial eligible business...."
          create_business(actor:, name: "GHAS Self Serve Trial Eligible Business", org_prefix: "ghas-self-serve-trial-eligible-b-org", committers: committers, options: options, type: :self_serve_trial_eligible)
          puts "Creating Advanced Security unbundled metered business...."
          create_business(actor:, name: "GHAS Unbundled Metered Business", org_prefix: "ghas-unbundled-metered-business-org", committers: committers, options: options, type: :metered, unbundled: true)
          puts "Creating Advanced Security unbundled Teams organization"
          create_organization(actor:, login: "ghas-unbundled-metered-teams-org", committers: committers, options: options, plan: "business", unbundled: true)
        end
      end

      def self.create_committers(login_prefix:, options:)
        1.upto(20).map do |i|
          login = "#{login_prefix}#{i + 1}"
          User.find_by(login: login)&.destroy if options[:reset]
          ReservedLogin.untombstone!(login)
          user = Objects::User.create(login: login)
        end
      end

      def self.create_organization(actor:, login:, committers:, options:, plan: "business_plus", unbundled: false)
        Organization.find_by(login: login)&.destroy if options[:reset]
        ReservedLogin.untombstone!(login)
        org = Objects::Organization.create(login: login, admin: actor, plan:)
        org.save!

        unless org.customer_account
          org.update!(billing_type: "card", customer_account: FactoryBot.create(:credit_card_customer_account, user: org))
        end

        org.bulk_add_members(committers)
        if unbundled
          org.set_customer_to_split_metered_offering(actor: actor)
        else
          org.mark_advanced_security_as_purchased_for_entity(actor: actor)
          org.set_advanced_security_seats_for_entity(seats: options[:seats], actor: actor)
        end

        unless options[:skip_repos]
          GhasCommitters.create_repo(actor:, owner: org, committers: committers, repo_name: "ghas-committers-1", unbundled:)
          GhasCommitters.create_repo(actor:, owner: org, committers: committers[..1], repo_name: "ghas-committers-2", unbundled:)
        end

        org.update!(billed_on: 10.days.from_now.to_date)

        org
      end

      def self.create_repo(actor:, owner:, committers:, repo_name:, unbundled: false, ghas_disabled: false)
        repo = Seeds::Objects::Repository.create(
          setup_master: true,
          owner_name: owner.login,
          repo_name: repo_name,
          is_public: false,
        )
        repo.reload
        branch = repo.default_branch

        # enable security products before creating commits
        # this is for TurboGHAS' benefit as it doesn't know GHAS has been enabled (yet)
        if ghas_disabled
          # do nothing
        elsif unbundled
          # enable security products - this seems like the preferred way to enable them
          SecurityProduct::ServiceManager.new(repo).toggle_services(owner, services_to_enable: [:code_security])
          SecurityProduct::ServiceManager.new(repo).toggle_services(owner, services_to_enable: [:token_scanning])
        else
          repo.enable_advanced_security!(actor: actor)
        end

        committers.each do |committer|
          Seeds::Objects::Commit.create(
            repo: repo,
            committer: committer,
            message: "test message",
            files: { "File.md" => Faker::Lorem.sentence }
          )
        end
        Seeds::Objects::Commit.random_create(
          repo: repo,
          users: owner.members,
          count: 5,
          branch: branch,
        )
      end

      def self.create_business(actor:, name:, org_prefix:, committers:, options:, type:, unbundled: false)
        Business.find_by(name: name)&.destroy if options[:reset]

        is_self_serve = type != :sales_purchased

        business = FactoryBot.create(
          :business,
          (:with_self_serve_payment if is_self_serve),
          name: name,
          owners: [actor],
        )
        FactoryBot.create(:billing_plan_subscription, customer: business.customer) if is_self_serve

        business.save!

        puts "Creating orgs for business #{business.name}..."

        orgs = 2.times.map do |i|
          login = "#{org_prefix}-#{i}"
          Organization.find_by(login: login)&.destroy if options[:reset]
          ReservedLogin.untombstone!(login)
          org = Objects::Organization.create(login: login, admin: actor)
          org.update!(business: business)
          org.bulk_add_members(committers)
          org
        end

        puts "Configuring business #{business.name}..."

        case type
        when :self_serve_purchased
          business.subscribe_to_advanced_security(seats: options[:seats], actor: actor, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        when :self_serve_trial
          business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
          business.subscribe_to_advanced_security_trial(actor: actor, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        when :self_serve_trial_eligible
          # nothing to do
        when :sales_purchased
          business.mark_advanced_security_as_purchased_for_entity(actor: actor)
          business.set_advanced_security_seats_for_entity(seats: options[:seats], actor: actor)
        when :metered
          business.mark_advanced_security_as_purchased_for_entity(actor: actor)
          business.mark_advanced_security_as_metered_for_entity(actor: actor)
        end

        if unbundled
          business.set_customer_to_split_metered_offering(actor: actor)
        end

        business.save!

        puts "Creating repos for business #{business.name}..."

        ghas_disabled = type == :self_serve_trial_eligible

        GhasCommitters.create_repo(actor:, owner: orgs.first, committers: committers, repo_name: "ghas-committers-1", unbundled:, ghas_disabled:) unless options[:skip_repos]
        GhasCommitters.create_repo(actor:, owner: orgs.first, committers: committers[..1], repo_name: "ghas-committers-2", unbundled:, ghas_disabled:) unless options[:skip_repos]
        GhasCommitters.create_repo(actor:, owner: orgs.second, committers: committers[..1], repo_name: "ghas-committers-2", unbundled:, ghas_disabled:) unless options[:skip_repos]

        business
      end
    end
  end
end
