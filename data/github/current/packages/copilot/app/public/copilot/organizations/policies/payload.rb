# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class Payload < ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper

        sig { params(organization: ::Copilot::Organization, user: ::User).void }
        def initialize(organization:, user:)
          @organization = organization
          @user = user
          @use_refactor = T.let(@organization.feature_flag_enabled?(:copilot_org_settings_refactor, default: false), T::Boolean)
        end

        sig { override.returns(String) }
        def route_id
          "copilotForBusinessPoliciesRoute"
        end

        sig { override.returns(T::Hash[String, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def payload
          call.transform_keys(&:to_s)
        end

        sig { returns(Copilot::Types::PoliciesIndexPayload) }
        def call
          copilot_business = @organization.copilot_business

          can_edit_snippy = true
          can_edit_editor_chat = true
          can_edit_mobile_chat = true
          can_edit_cli = true
          can_edit_desktop = @organization.feature_flag_enabled_or_raise?(:copilot_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_editor_preview_features = true
          can_edit_agent_mode = @organization.feature_flag_enabled_or_raise?(:copilot_agent_mode_show_policy) || false # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          can_edit_copilot_for_dotcom = true
          can_edit_dotcom_bing_access = true
          can_edit_user_feedback_opt_in = true
          can_see_copilot_chat_for_dotcom = true
          can_see_copilot_desktop = @organization.feature_flag_enabled_or_raise?(:copilot_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_dotcom_bing_access = !GitHub.multi_tenant_enterprise?
          can_edit_copilot_extensions = true
          can_edit_private_telemetry = true
          can_edit_beta_features_opt_in = true
          can_edit_usage_metrics_policy = false
          can_edit_code_review = @organization.feature_flag_enabled?(:copilot_code_review_policy, default: false)
          can_edit_swe_agent = true
          can_edit_mcp = true
          can_edit_mcp_registry = true
          can_edit_mcp_registry_access = true
          can_edit_spark = true
          can_edit_insights = @organization.feature_flag_enabled_or_raise?(:copilot_insights) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          can_see_editor_preview_features = @organization.feature_flag_enabled_or_raise?(:copilot_next_edit_suggestions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_agent_mode = @organization.feature_flag_enabled_or_raise?(:copilot_agent_mode_show_policy) || false # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_code_review = @organization.feature_flag_enabled?(:copilot_code_review_policy, default: false)
          can_see_swe_agent = !GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, @organization.organization_object, default: false)
          can_see_mcp = !GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, @organization.organization_object, default: false)
          can_see_insights = @organization.feature_flag_enabled_or_raise?(:copilot_insights) && !GitHub.multi_tenant_enterprise? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          # Only show if user has the feature flag enabled
          can_see_spark = @user.feature_flag_enabled_or_raise?(:spark_access_copilot_policy) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_mcp_registry = @organization.feature_flag_enabled_or_raise?(:copilot_mcp_registry) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage


          if copilot_business
            # if the business has an explicit policy, this user cannot edit it. So lets check for it.
            can_edit_snippy = copilot_business.no_public_code_suggestions_policy?
            can_edit_editor_chat = copilot_business.no_chat_policy?
            can_edit_mobile_chat = copilot_business.no_mobile_chat_policy?
            can_edit_copilot_for_dotcom = copilot_business.copilot_for_dotcom_no_policy?
            can_edit_dotcom_bing_access = copilot_business.bing_github_chat_no_policy?
            can_edit_user_feedback_opt_in = copilot_business.user_feedback_opt_in_no_policy?
            can_edit_cli = copilot_business.cli_no_policy?
            can_edit_desktop = copilot_business.feature_flag_enabled_or_raise?(:copilot_desktop) && (copilot_business.desktop_no_policy? || copilot_business.desktop_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_editor_preview_features = copilot_business.editor_preview_features_no_policy? || copilot_business.editor_preview_features_unconfigured?
            can_edit_agent_mode = ((copilot_business.agent_mode_no_policy? || copilot_business.agent_mode_unconfigured?) && @organization.feature_flag_enabled_or_raise?(:copilot_agent_mode_show_policy)) || false # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_copilot_extensions = copilot_business.copilot_extensions_no_policy?
            can_edit_private_telemetry = copilot_business.private_telemetry_no_policy?
            can_edit_usage_metrics_policy = copilot_business.telemetry_aggregation_no_policy?
            can_edit_beta_features_opt_in = copilot_business.beta_features_github_chat_no_policy?
            can_edit_swe_agent = copilot_business.swe_agent_no_policy?
            can_edit_mcp = copilot_business.mcp_no_policy?
            can_edit_spark = copilot_business.spark_no_policy?
            can_edit_insights = copilot_business.feature_flag_enabled_or_raise?(:copilot_insights) && copilot_business.insights_no_policy? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_code_review = copilot_business.feature_flag_enabled?(:copilot_code_review_policy, default: false) && copilot_business.code_review_no_policy?
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            can_see_copilot_desktop ||= copilot_business.feature_flag_enabled_or_raise?(:copilot_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_editor_preview_features = copilot_business.feature_flag_enabled_or_raise?(:copilot_next_edit_suggestions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_agent_mode = copilot_business.feature_flag_enabled_or_raise?(:copilot_agent_mode_show_policy) || false # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_swe_agent = (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, copilot_business.business_object, default: false)) && @organization.swe_agent_eligible?(@organization, copilot_business)
            can_see_mcp = (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, copilot_business.business_object, default: false)) && @organization.swe_agent_eligible?(@organization, copilot_business)
            can_see_insights = copilot_business.feature_flag_enabled_or_raise?(:copilot_insights) && !GitHub.multi_tenant_enterprise? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_code_review ||= copilot_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)
            can_edit_mcp_registry = copilot_business.mcp_no_policy?
            can_edit_mcp_registry_access = copilot_business.mcp_no_policy?
          else
            can_edit_usage_metrics_policy = true
          end

          snippy_setting = if @organization.allow_public_code_suggestions?
            "allowed"
          else
            "blocked"
          end

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            editor_chat: migratable_policy_hash({
              manages: "copilot_editor_chat_enabled",
              configurable: can_edit_editor_chat,
              visible: true,
              displayname: Copilot::COPILOT_CHAT_IN_IDE,
              helpurl: Copilot::COPILOT_CHAT_EDITOR_DOCS,
              helptext: "Learn more about Copilot in your editor.",
              description: "If enabled, members of this organization will have access to #{Copilot::COPILOT_CHAT_IN_IDE}.",
              options: make_general_menu_options(@organization.copilot_chat_setting),
              preview: false,
            }, policy_class: Copilot::Policies::EditorChat),
            mobile_chat: migratable_policy_hash({
              manages: "copilot_mobile_chat",
              configurable: can_edit_mobile_chat,
              visible: true,
              displayname: Copilot::COPILOT_CHAT_IN_MOBILE,
              helpurl: Copilot::COPILOT_CHAT_MOBILE_DOCS,
              helptext: "Learn more about Copilot in GitHub Mobile.",
              description: "If enabled, members of this organization will have access to #{Copilot::COPILOT_CHAT_IN_MOBILE}.",
              options: make_general_menu_options(@organization.mobile_chat),
              preview: false,
            }, policy_class: Copilot::Policies::MobileChat),
            editor_preview_features: migratable_policy_hash({
              manages: "copilot_editor_preview_features",
              configurable: can_edit_editor_preview_features,
              visible: can_see_editor_preview_features,
              displayname: Copilot::EDITOR_PREVIEW_FEATURES,
              helpurl: nil,
              helptext: nil,
              description: "If enabled, members of this organization will have access to editor preview features, including MCP servers.",
              options: make_general_menu_options(@organization.editor_preview_features),
              preview: true,
            }, policy_class: Copilot::Policies::EditorPreviewFeatures),
            agent_mode: migratable_policy_hash({
              manages: "copilot_agent_mode",
              configurable: can_edit_agent_mode,
              visible: can_see_agent_mode,
              displayname: Copilot::AGENT_MODE,
              helpurl: nil,
              helptext: nil,
              description: "If enabled, members of this organization will have access to agent mode.",
              options: make_general_menu_options(@organization.agent_mode),
              preview: false,
            }, policy_class: Copilot::Policies::AgentMode),
            # never displayed but must configure all fields for sorbet
            automatic_code_review: migratable_policy_hash({
              manages: "automatic_code_review",
              configurable: false,
              visible: false,
              helpurl: nil,
              helptext: nil,
              displayname: Copilot::AUTOMATIC_CODE_REVIEW,
              description: "If enabled, members of this organization will have access to automatic code review features.",
              options: make_menu_options([]),
              preview: false,
            }, policy_class: Copilot::Policies::AutomaticCodeReview),
            snippy: migratable_policy_hash({
              manages: "copilot_public_code_suggestions",
              configurable: can_edit_snippy,
              visible: true,
              displayname: Copilot::COPILOT_PUBLIC_CODE_SUGGESTIONS,
              helpurl: nil,
              helptext: nil,
              description: "Copilot can allow or block suggestions matching public code.",
              options: make_general_menu_options(snippy_setting, Copilot::Policies::Menus::ALLOW_OR_BLOCK),
              preview: false,
            }, policy_class: Copilot::Policies::Snippy, menu_items: Copilot::Policies::Menus::ALLOW_OR_BLOCK),
            cli: migratable_policy_hash_legacy({
              manages: "cli",
              configurable: can_edit_cli,
              visible: nil,
              options: make_general_menu_options(@organization.cli)
            }, policy_class: Copilot::Policies::Cli),
            desktop: migratable_policy_hash({
              manages: "desktop",
              configurable: can_edit_desktop,
              visible: can_see_copilot_desktop,
              displayname: Copilot::COPILOT_DESKTOP,
              helpurl: Copilot::COPILOT_IN_DESKTOP_DOCUMENTATION,
              helptext: "Learn more about Copilot in GitHub Desktop.",
              description: "If enabled, members of this organization will get Copilot assistance in GitHub Desktop.",
              options: make_general_menu_options(@organization.desktop),
              preview: !@organization.feature_flag_enabled_or_raise?(:copilot_desktop_no_preview_badge), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Desktop),
            copilot_for_dotcom: migratable_policy_hash_legacy({
              manages: "copilot_for_dotcom",
              configurable: can_edit_copilot_for_dotcom,
              visible: can_see_copilot_chat_for_dotcom,
              options: make_menu_options([
                Copilot::Policies::MenuItems::CopilotForDotcom::Enabled,
                Copilot::Policies::MenuItems::CopilotForDotcom::Disabled,
              ])
            }, policy_class: Copilot::Policies::Dotcom),
            bing_github_chat: migratable_policy_hash({
              manages: "bing_github_chat",
              configurable: can_edit_dotcom_bing_access,
              visible: can_see_dotcom_bing_access,
              displayname: Copilot::COPILOT_BING_ACCESS,
              description: "Copilot can answer questions about new trends and give improved answers, via Bing.",
              helpurl: Copilot::MICROSOFT_PRIVACY_STATEMENT_URL,
              helptext: "See the Microsoft Privacy Statement.",
              options: make_general_menu_options(@organization.bing_github_chat),
              preview: false,
            }, policy_class: Copilot::Policies::Bing),
            copilot_user_feedback_opt_in: migratable_policy_hash_opt_in({
              manages: "copilot_user_feedback_opt_in",
              configurable: can_edit_user_feedback_opt_in,
              visible: can_see_copilot_chat_for_dotcom,
              enabled: @organization.user_feedback_opt_in_enabled?,
            }, policy_class: Copilot::Policies::UserFeedback),
            copilot_beta_features_opt_in: migratable_policy_hash_opt_in({
              manages: "copilot_beta_features_opt_in",
              configurable: can_edit_beta_features_opt_in,
              visible: true,
              enabled: @organization.beta_features_github_chat_enabled?,
            }, policy_class: Copilot::Policies::DotcomBetaFeatures),
            copilot_extensions: migratable_policy_hash_legacy({
              manages: "copilot_extensions",
              configurable: can_edit_copilot_extensions,
              visible: nil,
              options: make_menu_options([
                Copilot::Policies::MenuItems::CopilotExtensions::Enabled,
                Copilot::Policies::MenuItems::CopilotExtensions::Disabled,
              ])
            }, policy_class: Copilot::Policies::Extensions),
            private_telemetry: migratable_policy_hash_legacy({
              manages: "private_telemetry",
              configurable: can_edit_private_telemetry,
              visible: nil,
              options: make_menu_options([
                Copilot::Policies::MenuItems::PrivateTelemetry::Allowed,
                Copilot::Policies::MenuItems::PrivateTelemetry::Blocked,
              ])
            }, policy_class: Copilot::Policies::PrivateTelemetry),
            mcp:  migratable_policy_hash({
              manages: "copilot_mcp",
              configurable: can_edit_mcp,
              visible: can_see_mcp,
              helpurl: "https://docs.github.com/en/copilot/customizing-copilot/extending-copilot-chat-with-mcp",
              helptext: "See MCP docs for Copilot Chat and Coding Agent.",
              description: "If enabled, users can configure Model Context Protocol (MCP) servers for Copilot in #{@organization.feature_flag_enabled?(:mcp_clients_ga_release, default: false) ? 'all Copilot editors and Coding Agent. Note that Coding Agent is in public preview.' : 'Visual Studio Code and Coding Agent. MCP support is GA in VS Code, while Coding Agent is in public preview.'}",
              displayname: Copilot::COPILOT_MCP_SERVERS,
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.mcp_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.mcp_disabled?),
              ].map(&:to_h).compact,
              preview: false,
            }, policy_class: Copilot::Policies::Mcp),
            mcp_registry: {
              manages: "copilot_mcp_registry",
              displayname: Copilot::COPILOT_MCP_REGISTRY,
              description: nil,
              visible: can_see_mcp_registry,
              configurable: can_edit_mcp_registry,
              options: nil,
              helptext: nil,
              helpurl: nil,
              preview: false,
              submitPath: Rails.application.routes.url_helpers.settings_org_copilot_mcp_registry_url_create_or_update_path(@organization),
              mcpRegistryUrl: @organization.mcp_registry_url,
              mcpRegistryId: @organization.mcp_registry_id,
              isGA: @organization.feature_flag_enabled?(:copilot_mcp_registry_ga, default: false),
            },
            mcp_registry_access: {
              manages: "copilot_mcp_registry_access",
              displayname: Copilot::COPILOT_MCP_REGISTRY_ACCESS,
              description: "Control which MCP servers are allowed based on your registry configuration. #{!@organization.feature_flag_enabled?(:copilot_mcp_registry_ga, default: false) ? 'Allowlisting is currently only supported on VS Code Insiders.' : ''}",
              visible: can_see_mcp_registry,
              configurable: can_edit_mcp_registry_access,
              options: make_menu_options([
                Copilot::Policies::MenuItems::McpRegistryAccess::AllowAll,
                Copilot::Policies::MenuItems::McpRegistryAccess::RegistryOnly,
              ]),
              helptext: "View docs on MCP registry allow lists.",
              helpurl: "https://gh.io/mcp-registry-allow-lists",
              preview: false,
              submitPath: Rails.application.routes.url_helpers.settings_org_copilot_mcp_registry_url_create_or_update_path(@organization),
              mcpRegistryUrl: nil,
              mcpRegistryId: @organization.mcp_registry_id,
              isGA: @organization.feature_flag_enabled?(:copilot_mcp_registry_ga, default: false),
            },
            copilot_usage_metrics_policy: migratable_policy_hash({
              manages: "copilot_usage_metrics_policy",
              configurable: can_edit_usage_metrics_policy,
              visible: true,
              displayname: Copilot::COPILOT_METRICS_API_NAME,
              description: "If enabled, organizations administrators can query the #{Copilot::COPILOT_METRICS_API_NAME} for insights into Copilot usage.",
              helptext: "Learn more about the Copilot Metrics API.",
              helpurl: Copilot::COPILOT_USAGE_METRICS_API_DOCS,
              options: make_general_menu_options(@organization.usage_telemetry_api),
              preview: false,
            }, policy_class: Copilot::Policies::MetricsApi),
            code_review:  migratable_policy_hash_legacy({
              manages: "copilot_code_review",
              configurable: can_edit_code_review,
              visible: can_see_code_review,
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.code_review_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.code_review_disabled?),
              ].map(&:to_h).compact,
            }, policy_class: Copilot::Policies::CodeReview),
            code_review_beta_features: migratable_policy_hash_opt_in({
              manages: "copilot_code_review_beta_features",
              configurable: can_edit_code_review,
              visible: can_see_code_review && @organization.code_review_enabled?,
              enabled: @organization.code_review_beta_features_enabled?,
            }, policy_class: Copilot::Policies::CodeReviewBetaFeatures),
            swe_agent:  migratable_policy_hash({
              manages: "copilot_swe_agent",
              configurable: can_edit_swe_agent,
              visible: can_see_swe_agent,
              helpurl: "https://gh.io/assigncopilot",
              helptext: "Learn more.",
              description: "If enabled, users assigned a Copilot license from this organization will have access to #{Copilot::COPILOT_SWE_AGENT} in repositories where it is enabled. This feature may use models which are not enabled on your Models settings page.",
              displayname: "#{Copilot::COPILOT_SWE_AGENT} access",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.swe_agent_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.swe_agent_disabled?),
              ].map(&:to_h).compact,
              preview: true,
            }, policy_class: Copilot::Policies::CodingAgent),
            spark: migratable_policy_hash({
              manages: "copilot_spark",
              configurable: can_edit_spark,
              visible: can_see_spark,
              helpurl: "https://gh.io/responsible-use-of-github-spark",
              helptext: "Learn more about #{Copilot::SPARK_NAME}.",
              displayname: Copilot::SPARK_NAME,
              description: "If enabled, members of your enterprise will have access to #{Copilot::SPARK_NAME}.",
              options: make_general_menu_options(@organization.spark),
              preview: true,
            }, policy_class: Copilot::Policies::Spark),
            insights: migratable_policy_hash({
              manages: "copilot_insights",
              configurable: can_edit_insights,
              visible: can_see_insights,
              helpurl: Copilot::COPILOT_INSIGHTS_DOCS,
              helptext: "Learn more about the available insights and how to interpret them.",
              description: "If enabled, organization admins can access Copilot metrics within organization-level insights.",
              displayname: Copilot::COPILOT_INSIGHTS,
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.insights_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.insights_disabled?),
              ].map(&:to_h).compact,
              preview: true,
            }, policy_class: Copilot::Policies::Insights),
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            },
            overages: get_overage_policies
          }

        end

        private

        sig do params(items: T::Array[T.class_of(Copilot::Policies::MenuItems::Base)])
          .returns(T::Array[Copilot::Types::MenuItemHashType])
        end
        def make_menu_options(items)
          items.map do |menu_item|
            menu_item.new(copilot_configurable: @organization).to_h
          end.compact
        end

        sig do params(value: String, items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)])
          .returns(T::Array[Copilot::Types::MenuItemHashType])
        end
        def make_general_menu_options(value, items = Copilot::Policies::Menus::DEFAULT)
          items.map do |menu_item|
            menu_item.new(copilot_configurable: @organization, checked: value == menu_item.value).to_h
          end.compact
        end

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: String, description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def build_policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            helptext: helptext,
            description: description,
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(policy_class.value(@organization), menu_items),
            preview: policy_class.preview?(@organization),
          }
        end

        sig { params(control_hash: Copilot::Types::PoliciesIndexPayloadNewAspect, policy_class: Copilot::Types::OrgMutablePolicy, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def migratable_policy_hash(control_hash, policy_class:, menu_items: Copilot::Policies::Menus::DEFAULT)
          if @use_refactor
            return build_policy_hash(policy_class, helptext: control_hash[:helptext], description: control_hash[:description], menu_items:)
          end

          control_hash
        end

        sig { params(control_hash: Copilot::Types::PoliciesIndexPayloadAspect, policy_class: Copilot::Types::OrgMutablePolicy, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadAspect) }
        def migratable_policy_hash_legacy(control_hash, policy_class:, menu_items: Copilot::Policies::Menus::DEFAULT)
          if @use_refactor
            return {
              manages: policy_class.config_name,
              visible: policy_class.viewable_by_org?(@organization),
              configurable: policy_class.editable_by?(@organization),
              options: make_general_menu_options(policy_class.value(@organization), menu_items),
              preview: policy_class.preview?(@organization),
            }
          end

          control_hash
        end

        sig { params(control_hash: Copilot::Types::PoliciesIndexPayloadOptInAspect, policy_class: Copilot::Types::OrgMutablePolicy).returns(Copilot::Types::PoliciesIndexPayloadOptInAspect) }
        def migratable_policy_hash_opt_in(control_hash, policy_class:)
          if @use_refactor
            return {
              manages: policy_class.config_name,
              visible: policy_class.viewable_by_org?(@organization),
              configurable: policy_class.editable_by?(@organization),
              enabled: policy_class.enabled?(@organization)
            }
          end

          control_hash
        end


        sig { returns(Copilot::Types::BillingOveragesPayload) }
        def get_overage_policies
          return {
            visible: false,
            value: false,
            copilot_premium_request: { value: false, visible: false },
            coding_agent: { value: false, visible: false },
            spark: { value: false, visible: false }
          } unless @organization.feature_flag_enabled?(:billing_platform_overages_policies_enabled, default: false)

          policies = {
            copilot_premium_request: { type: "sku", name: "copilot_premium_request" },
            coding_agent: { type: "product", name: "coding_agent" },
            spark: { type: "product", name: "spark" }
          }

          responses = {}
          policies.each do |key, details|
            responses[key] = billing_platform_client.get_overage_policy(
              customer_id: @organization.customer&.id,
              overage_policy_type: details[:type],
              name: details[:name],
              is_for_business: true
            )
          end
          has_error = responses.values.any? { |response| response.is_a?(::Billing::Platform::Api::Error) }

          if has_error
            error_response = responses.values.find { |response| response.is_a?(::Billing::Platform::Api::Error) }
            Failbot.report(error_response)
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get_overage_policy"])
          else
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get_overage_policy"])
          end

          result = {
            visible: !has_error,
            value: false,
            copilot_premium_request: { value: false, visible: !has_error },
            coding_agent: { value: false, visible: !has_error },
            spark: { value: false, visible: !has_error }
          }

          unless has_error
            policies.keys.each do |policy_key|
              response = responses[policy_key]
              if !response.is_a?(::Billing::Platform::Api::Error) && response[:overagePolicy][:enabled]
                result[policy_key][:value] = true
              end
            end
          end

          # set this value to the copilot_premium_request value for backwards compatibility as github-ui will check for this before both parts are rolled out
          result[:value] = result[:copilot_premium_request][:value]
          result
        end

        sig { returns(::Billing::Platform::Api::Client) }
        def billing_platform_client
          ::Billing::Platform::Api::Client.new
        end
      end
    end
  end
end
