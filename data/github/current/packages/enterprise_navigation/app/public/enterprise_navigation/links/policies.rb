# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Policies
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include ResilienceHelper
      include ActionView::Helpers::CaptureHelper
      include EnterpriseNavigation::Links::SharedDependency
      include SecretScanning::Features::FeatureFlagHelper

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def policies_menu_groups
        [repository_policies_group, other_policies_group]
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def repository_policies_group
        menu_items = []

        if @business && business_owner?
          menu_items << repository_menu_item if !basic_account? && @business.enterprise_rulesets_enabled?
          menu_items << code_rules_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled?
          menu_items << rule_insights_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled?
          menu_items << code_rule_bypass_requests_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled?
          menu_items << business_properties_menu_item if !basic_account? && CustomProperties::Public.enterprise_properties_enabled?(@business)
        end
        EnterpriseNavigation::Group.new(
          name: "Repository",
          type: EnterpriseNavigation::GroupType::FOLDING,
          icon: :repo,
          label: EnterpriseNavigation::Label::PREVIEW,
          links: menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def policies_menu_items
        policies_menu_groups.flat_map(&:links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def other_policies_group
        menu_items = []
        if @business
          if business_owner?
            menu_items << member_privilege_menu_item unless basic_account?
            menu_items << codespaces_menu_item if GitHub.codespaces_enabled? && !basic_account?

            if GitHub.copilot_enabled?
              # This ended up getting too complicated, so we're breaking it back down to basics.
              # We can do one of three things here based on the enterprise:
              # 1. show a link to the first run flow
              # 2. show a link to Copilot Enterprise Settings page (this is if they are a full GHEC enterprise who HAS configured things)
              # 3. don't show anything
              #
              # The logic breaks down like this:
              #
              # If they are a GHEC trial
              #   if they have CFB trial organization
              #     show copilot_sub_menu_item
              #   else
              #     hide menu
              #   end
              # elsif they are GHEC enterprise
              #   if they have a copilot configuration
              #     show copilot_sub_menu_item
              #   else
              #     show copilot_first_run_flow_sub_menu_item
              #   end
              # end
              if @business.trial? # this is a GHEC trial
                if ::Copilot::BusinessTrial.find_by(trialable_id: business&.organization_ids, state: ::Copilot::BusinessTrial::ACTIVE_STATES) # they have an active CFB trial
                  menu_items << copilot_menu_item(standalone_business: false) # show sub menu, hiding organization settings
                end # else do nothing
              else # this is a full GHEC account
                if copilot_eligible_for_first_run_flow?
                  menu_items << copilot_first_run_flow_sub_menu_item
                else
                  menu_items << copilot_menu_item(standalone_business: @business.copilot_licensing_enabled?)
                end
              end
            end

            # Only Copilot policies are shown to basic accounts
            unless basic_account?
              menu_items << actions_menu_item if GitHub.actions_enabled?
              menu_items << hosted_compute_networking_menu_item if hosted_compute_networking_menu_item_available?
              menu_items << projects_menu_item
              menu_items << options_menu_item if GitHub.single_business_environment?
              menu_items << code_security_policies_menu_item if show_code_security_policies_menu_item?
              menu_items << personal_access_token_policies_menu_item if GitHub.patsv2_enabled?
              menu_items << sponsors_menu_item if show_sponsors_menu_item?
              menu_items << models_menu_item if show_models_menu_item?
            end
          else
            menu_items << code_security_policies_menu_item if show_code_security_policies_menu_item?
          end
        end
        EnterpriseNavigation::Group.new(
          links: menu_items,
          type: EnterpriseNavigation::GroupType::FLAT,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def repository_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Repository",
          link_path: settings_repository_policies_enterprise_path(@business),
          highlight: :business_repository_policies,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_rules_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code",
          link_path: settings_code_rules_enterprise_path(@business),
          highlight: :business_code_rulesets,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def rule_insights_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code insights",
          link_path: settings_code_rule_insights_enterprise_path(@business),
          highlight: :business_code_rule_insights,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_rule_bypass_requests_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code ruleset bypasses",
          link_path: settings_code_rules_bypass_requests_enterprise_path(@business),
          highlight: :business_code_rule_bypass_requests,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def business_properties_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Custom properties",
          link_path: settings_custom_properties_enterprise_path(@business),
          highlight: :business_custom_properties_settings,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def member_privilege_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Member privileges",
          link_path: settings_member_privileges_enterprise_path(@business),
          highlight: :business_member_privileges_settings,
          icon: :shield,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def codespaces_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Codespaces",
          link_path: settings_codespaces_enterprise_path(@business),
          highlight: :business_codespaces_settings,
          icon: :codespaces,
        )
      end

      sig { params(standalone_business: T::Boolean).returns EnterpriseNavigation::Link }
      def copilot_menu_item(standalone_business: false)
        EnterpriseNavigation::Link.new(
          link_name: standalone_business ? "Copilot Business" : "Copilot",
          link_path: settings_copilot_enterprise_path(@business),
          highlight: :business_copilot_settings,
          icon: :copilot,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def copilot_first_run_flow_sub_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Copilot",
          link_path: settings_copilot_enterprise_path(@business),
          highlight: :business_copilot_settings,
          icon: :copilot,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def actions_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Actions",
          link_path: settings_actions_enterprise_path(@business),
          # No selected-link reference is available for: business_actions_settings_edit_larger_runner
          highlight: %i(
            business_actions_settings
            business_actions_settings_runners
            business_actions_settings_add_new_runner
            business_actions_settings_runner_details
            business_actions_settings_runner_group
            business_actions_settings_runner_groups
            business_actions_settings_add_larger_runner
            business_actions_settings_edit_larger_runner
            business_actions_settings_larger_runner_details
            business_actions_settings_hosted_runners
            business_actions_settings_custom_images
          ),
          icon: :play,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def hosted_compute_networking_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Hosted compute networking",
          link_path: enterprise_hosted_compute_networking_path(@business),
          highlight: :hosted_compute_networking,
          icon: :cpu,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def projects_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Projects",
          link_path: settings_projects_enterprise_path(@business),
          highlight: :business_projects_settings,
          icon: :project,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def options_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Options",
          link_path: enterprise_admin_center_options_path(@business),
          highlight: :business_admin_center_options,
          icon: :gear,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_policies_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Advanced Security",
          link_path: settings_security_analysis_policies_enterprise_path(@business),
          highlight: %i(
            business_code_security_and_analysis
            business_advanced_security
          ),
          icon: :shield,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def personal_access_token_policies_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Personal access tokens",
          link_path: settings_personal_access_tokens_enterprise_path(@business),
          highlight: :business_personal_access_token_policy_settings,
          icon: :key,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def sponsors_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Sponsors",
          link_path: settings_sponsors_enterprise_path(@business),
          highlight: :sponsors_settings,
          icon: :heart,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def models_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Models",
          link_path: settings_models_enterprise_path(@business),
          highlight: :models_settings,
          icon: :"ai-model"
        )
      end

      sig { returns T::Boolean }
      memoize def hosted_compute_networking_menu_item_available?
        return false if GitHub.single_business_environment?
        return false if @business&.downgraded_to_free_plan?
        true
      end

      sig { returns(T::Boolean) }
      memoize def code_security_policies_menu_item_available?
        return false unless @business
        return true if ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
        return true if @business.advanced_security_purchased?
        return true if SecretScanning::Features::Business::TokenScanning.new(@business).feature_available?
        false
      end

      sig { returns(T::Boolean) }
      memoize def show_code_security_policies_menu_item?
        return false unless @business
        return false unless code_security_policies_menu_item_available?
        SecurityProduct::Permissions::BusinessAuthz.new(@business, actor: user).can_view_code_security_policies?
      end

      sig { returns(T::Boolean) }
      memoize def show_sponsors_menu_item?
        GitHub.sponsors_enabled? && @business.present?
      end

      sig { returns(T::Boolean) }
      memoize def show_models_menu_item?
        return false unless @business
        @business.enterprise_managed? && !@business.copilot_licensing_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def active_copilot_trial?
        return false unless business
        with_database_error_fallback(fallback: false) do
          !!Copilot::BusinessTrial.find_by(trialable_id: business&.organization_ids, state: Copilot::BusinessTrial::ACTIVE_STATES)
        end
      end

      sig { returns(T::Boolean) }
      memoize def copilot_eligible_for_first_run_flow?
        return false unless b = business
        with_database_error_fallback(fallback: false) do
          !!::Copilot::Business.new(b).eligible_for_first_run_flow?
        end
      end
    end
  end
end
