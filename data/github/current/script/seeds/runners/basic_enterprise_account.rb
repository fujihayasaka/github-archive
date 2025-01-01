# typed: true
# frozen_string_literal: true

require_relative "../runner"

module Seeds
  class Runner
    class BasicEnterpriseAccount < Seeds::Runner
      def self.help
        <<~HELP
        Seed enterprise accounts with seats_plan_type set to basic.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {
        emu: false,
        onboard_to_billing_platform: false,
      })
        require_relative "../factory_bot_loader"

        if !options[:emu]
          owner = Seeds::Objects::User.monalisa
          business = FactoryBot.create(:business, :default_managed, { owners: [Objects::User.monalisa], seats_plan_type: :basic })
          puts "Created enterprise account with slug #{business.slug}"
        else
          name = Faker::Company.name.first(30)
          slug = name.parameterize
          shortcode = name.parameterize.first(3)
          business = FactoryBot.create(:business, { name: name, slug: slug, shortcode: shortcode, business_type: :enterprise_managed, seats_plan_type: :basic })
          puts "Created enterprise account with slug #{business.slug} and user #{business.owners.first&.login}"
          puts "Login as user #{business.owners.first&.login} to test"
        end

        if options[:onboard_to_billing_platform]
          business.customer.onboard_to_billing_platform_excluding_ghas_and_ghec
          puts "#{business.slug} onboarded to billing platform"
        end
      end
    end
  end
end
