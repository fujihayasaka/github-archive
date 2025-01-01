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
        enable_models_for_org(copilot_org, user: monalisa)
        enable_copilot_for_org(copilot_org, user: monalisa)
        create_custom_models(copilot_org, user: monalisa)
        create_integration
      end

      private

      sig { void }
      def create_integration
        if Apps::Privileged.integration(:copilot_byok).present?
          puts "Copilot BYOK app already exists"
        else
          puts "Creating the Copilot BYOK app..."
          Apps::Privileged::CopilotByok.seed_database!
        end
      end

      sig { void }
      def enable_features
        %i(copilot_byok).each do |flag|
          puts "Enabling #{flag} feature flag..."
          FeatureFlag.vexi_management.enable_feature_flag(flag)
        end
      end

      sig { params(org: ::Organization, user: ::User).void }
      def enable_models_for_org(org, user:)
        business = org.business
        biz_success = if business
          business.enable_models_access(user) && business.enable_custom_models(user)
        else
          true
        end
        if biz_success
          if org.enable_models_access(user)
            biz_suffix = business ? " and enterprise #{business.name}" : ""
            puts "\nEnabled GitHub Models access for @#{org.display_login}#{biz_suffix}"
          else
            biz_suffix = business ? " but enabled it for enterprise #{business.name}" : ""
            puts "\nFailed to enable GitHub Models access for @#{org.display_login}#{biz_suffix}"
          end
        else
          puts "\nFailed to enable GitHub Models access for enterprise #{business.name}"
        end
      end

      sig { params(org: ::Organization, user: ::User).void }
      def enable_copilot_for_org(org, user:)
        puts "\nEnabling Copilot for @#{org.display_login}..."
        copilot_org = Copilot::Organization.new(org)
        copilot_org.enable_copilot!

        business = org.business
        if business
          puts "\nEnabling Copilot for enterprise #{business.name}..."
          copilot_biz = Copilot::Business.new(business)
          copilot_biz.enable_copilot_for_all_organizations!
        end
      end

      sig { params(org: ::Organization, user: ::User).returns(::CopilotByok::CustomModel) }
      def create_custom_models(org, user:)
        trait = %i(openai azureai).sample
        custom_key_count = org.copilot_custom_keys.count
        custom_key_name = "My_#{(custom_key_count + 1).ordinalize}_Custom_Key"
        puts "\nCreating Copilot #{trait} custom key '#{custom_key_name}' for @#{org.display_login}..."
        custom_key = FactoryBot.create(:copilot_byok_custom_key, trait, organization: org, actor: user,
          name: custom_key_name)

        puts "Creating Copilot custom model for @#{org.display_login}..."
        FactoryBot.create(:copilot_byok_custom_model, organization: org, custom_key: custom_key, actor: user)
      end

      sig { returns ::Organization }
      def copilot_org
        @copilot_org ||= ::Organization.find_by_login("copilot-business-org") || Seeds::Objects::Organization.create(login: "github",
          admin: monalisa)
      end

      sig { returns ::User }
      def monalisa
        @monalisa ||= Seeds::Objects::User.monalisa
      end
    end
  end
end
