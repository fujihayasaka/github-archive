# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class DefaultModelSettings < Seeds::Runner

      sig { returns(String) }
      def self.help
        <<~HELP
        - Creates an enterprise organization with Copilot features and default model settings enabled
        Use `-f` (force) flag to recreate from scratch.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"
        user = Seeds::Objects::User.monalisa
        enable_features
        copilot_enterprise_org(user)
      end

      sig { params(user: User).returns(Organization) }
      def self.copilot_enterprise_org(user)
        org_on_copilot_enterprise_name = "copilot-enterprise-org"
        org = Organization.find_by(login: org_on_copilot_enterprise_name)
        if org
          puts "➡️ Found @#{org}"
        else
          puts "➡️ Creating @#{org_on_copilot_enterprise_name}..."
          org = FactoryBot.create(:copilot_feature_enabled_enterprise_organization,
            :copilot_plan_enterprise,
            id: 2206, # to match https://github.com/github/copilot-api/blob/8a68ab88b9fdf79dd4f094136942ebe62ac1e1ad/pkg/kb/store/memory.go#L36
            name: org_on_copilot_enterprise_name,
            billing_email: T.must(user.emails.first).email,
            admins: [user],
          )
        end

        begin
          org.business.add_owner(user, actor: user)
        rescue Exception # rubocop:todo Lint/RescueException
        end

        # enable Bing skill at the business level
        b = ::Copilot::Business.new(org.business)
        b.copilot_for_dotcom_enabled!
        b.bing_github_chat_enabled!
        b.beta_features_github_chat_enabled!
        enable_free_billing_workaround(org.business)

        # enable additional models
        b.o1_enabled!

        # enable MCP
        b.mcp_enabled!

        # enable haiku 4.5
        b.configuration.bento_enabled!

        # enable Gpt 5
        b.configuration.obmb_enabled!

        begin
          FactoryBot.create(:copilot_seat_assignment, organization: org, assignable: user)
        rescue Exception # rubocop:todo Lint/RescueException
        end

        fancy_puts "Created org #{org.business.name}/#{org.display_login}", :success

        org
      end

      # enable :copilot_for_business_free to get around Copilot::Billable#copilot_billable? check in dev.
      # Without this things like the http://github.localhost/organizations/copilot-enterprise-org/settings/copilot/policies will simply redirect
      # to the seat assignments page.
      sig { params(business: Business).void }
      def self.enable_free_billing_workaround(business)
        Seeds::Objects::FeatureFlag.enable(feature_flag: :copilot_for_business_free, actor: business)
      end

      sig { params(message: String, type: Symbol, indent: T.nilable(Integer)).void }
      def self.fancy_puts(message, type, indent: 0)
        return unless Rails.env.development?
        indent_string = " " * (indent || 0) * 2
        icon = case type
        when :info
          "ℹ️ "
        when :loading
          "🌀"
        when :success
          "✅"
        else
          ""
        end
        puts "#{indent_string}#{icon} #{message}"
      end

      sig { void }
      def self.enable_features
        features = [
          :copilot_default_models_app,
          :use_setting_rules_copilot_models,
          :copilot_unconfigured_is_inherited_evaluate,
        ]

        if features.any?
          fancy_puts "Enabling feature flags...", :loading
          features.each do |feature|
            Seeds::Objects::FeatureFlag.enable(feature_flag: feature)
          end
          fancy_puts "Enabled feature flags", :success
        end
      end
    end
  end
end
