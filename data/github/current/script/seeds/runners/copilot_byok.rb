# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CopilotByok < Seeds::Runner
      def self.help
        <<~HELP
        Sets up Copilot BYOK (bring your own key) for custom models.
        HELP
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"
        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        enable_features

        enterprise = create_copilot_standalone_business(user: monalisa)
        create_custom_key_with_models(enterprise, user: monalisa, count: rand(4) + 1)

        enable_models_for_org_and_its_business(copilot_org, user: monalisa)
        enable_copilot_for_org_and_its_business(copilot_org, user: monalisa)
        create_custom_key_with_models(copilot_org, user: monalisa, count: rand(4) + 1)

        enterprise = copilot_org.business
        if enterprise
          custom_models = create_custom_key_with_models(enterprise, user: monalisa, count: rand(10) + 1)

          # Create potentially enough organizations to not fit within the limit from our
          # `GET /enterprises/:slug/settings/copilot/custom-model-orgs` endpoint, to test searching:
          orgs = create_organizations(enterprise, admin: monalisa, count: rand(105) + 1)
          enable_models_for_enterprise_orgs(orgs, custom_models, enterprise)
        end
      end

      private

      sig { void }
      def enable_features
        %i(
          copilot_for_business_free
          enterprise_ai_controls
        ).each do |flag|
          puts "Enabling #{flag} feature flag..."
          FeatureFlag.vexi_management.enable_feature_flag(flag)
        end
      end

      sig { params(user: ::User).returns(::Business) }
      def create_copilot_standalone_business(user:)
        biz = FactoryBot.create(:business, :copilot_standalone, owners: [user])
        puts "Created Copilot Standalone enterprise #{biz.name}, owned by @#{user}"
        Copilot::Business.new(biz).enable_copilot!
        biz
      end

      sig { params(org: ::Organization, user: ::User).void }
      def enable_models_for_org_and_its_business(org, user:)
        business = org.business
        biz_success = if business
          business.enable_models_access(user) && business.enable_custom_models(user) &&
            business.enable_copilot_custom_models(user)
        else
          true
        end
        if biz_success
          enable_models_for_org(org, user: user, success_suffix: business ? " and enterprise #{business.name}" : "",
            failure_suffix: business ? " but enabled it for enterprise #{business.name}" : "")
        else
          puts "Failed to enable GitHub Models access for enterprise #{business.name}"
        end
      end

      sig { params(org: ::Organization, user: ::User, success_suffix: String, failure_suffix: String).void }
      def enable_models_for_org(org, user:, success_suffix: "", failure_suffix: "")
        if org.enable_models_access(user)
          puts "Enabled GitHub Models access for @#{org.display_login}#{success_suffix}"
        else
          puts "Failed to enable GitHub Models access for @#{org.display_login}#{failure_suffix}"
        end
      end

      sig { params(org: ::Organization, user: ::User).void }
      def enable_copilot_for_org_and_its_business(org, user:)
        business = org.business
        if business
          puts "Enabling Copilot for enterprise #{business.name}..."
          copilot_biz = Copilot::Business.new(business)
          copilot_biz.enable_copilot_for_all_organizations!
        end
        enable_copilot_for_org(org, user: user)
      end

      sig { params(org: ::Organization, user: ::User).void }
      def enable_copilot_for_org(org, user:)
        puts "Enabling Copilot for @#{org.display_login}..."
        copilot_org = Copilot::Organization.new(org)
        copilot_org.enable_copilot!
        copilot_org.seat_management_allow_all!
      end

      sig do
        params(
          owner: T.any(::Business, ::Organization),
          user: ::User,
          count: Integer
        ).returns(T::Array[::CopilotByok::CustomModel])
      end
      def create_custom_key_with_models(owner, user:, count: 1)
        provider_trait = %i(openai azureai).sample
        custom_key_count = owner.copilot_custom_keys.count
        custom_key_name = "My_#{(custom_key_count + 1).ordinalize}_Custom_Key"
        owner_name = owner.is_a?(::Organization) ? "@#{owner.display_login}" : owner.slug
        puts "\nCreating Copilot #{provider_trait} custom key '#{custom_key_name}' for #{owner_name}..."
        key_factory_traits = [provider_trait]
        key_factory_attrs = { actor: user, name: custom_key_name }
        if owner.organization?
          key_factory_attrs[:organization] = owner
        else
          key_factory_traits << :enterprise
          key_factory_attrs[:business] = owner
        end
        custom_key = FactoryBot.create(:copilot_byok_custom_key, *key_factory_traits, key_factory_attrs)

        units = count == 1 ? "model" : "models"
        puts "Creating #{count} Copilot custom #{units} for #{owner_name}..."
        FactoryBot.create_list(:copilot_byok_custom_model, count, custom_key: custom_key, actor: user)
      end

      sig { params(business: ::Business, admin: ::User, count: Integer).returns(T::Array[::Organization]) }
      def create_organizations(business, admin:, count: 1)
        units = count == 1 ? "organization" : "organizations"
        puts "Creating #{count} #{units} in #{business.slug}..."
        orgs = T.let([], T::Array[::Organization])
        count.times do |i|
          login = Faker::Company.name.humanize.gsub(/[^A-Za-z0-9]+/, "") + "-#{i + 1}"
          org = FactoryBot.create(:organization, business: business, admin: admin, login: login)
          enable_models_for_org(org, user: admin)
          enable_copilot_for_org(org, user: admin)
          orgs << org
        end
        orgs
      end

      sig do
        params(
          orgs: T::Array[::Organization],
          custom_models: T::Array[::CopilotByok::CustomModel],
          business: ::Business
        ).void
      end
      def enable_models_for_enterprise_orgs(orgs, custom_models, business)
        policy = ::CopilotByok::CustomModelPolicy.new(business: business)
        models_to_globally_enable = Array.wrap(custom_models.sample(rand(custom_models.size / 2) + 1)).compact
        models_to_globally_enable.each do |custom_model|
          puts "Enabling #{custom_model.slug} for all orgs in #{business.name}..."
          policy.enable_custom_model_for_all_orgs(custom_model)
        end

        remaining_models = custom_models - models_to_globally_enable
        models_to_enable_for_specific_orgs = Array.wrap(remaining_models.sample(rand(remaining_models.size / 2) + 1))
          .compact
        models_to_enable_for_specific_orgs.each do |custom_model|
          orgs_to_get_model_access = Array.wrap(orgs.sample(rand(orgs.size / 2) + 1)).compact
          org_names = orgs_to_get_model_access.map(&:display_login).to_sentence
          puts "Enabling #{custom_model.slug} for org(s) #{org_names}..."
          policy.enable_custom_model_for_orgs(custom_model, org_ids: orgs_to_get_model_access.map(&:id))
        end
      end

      sig { returns ::Organization }
      def copilot_org
        @copilot_org ||= ::Organization.find_by_login("copilot-business-org") ||
          ::Organization.find_by_login("github") ||
          Seeds::Objects::Organization.create(login: "github", admin: monalisa)
      end

      sig { returns ::User }
      def monalisa
        @monalisa ||= Seeds::Objects::User.monalisa
      end
    end
  end
end
