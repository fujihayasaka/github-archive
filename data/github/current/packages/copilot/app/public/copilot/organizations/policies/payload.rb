# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_allowlist_client"
require "mcp_registry/enterprise_settings_client"

module Copilot
  module Organizations
    module Policies
      class Payload < ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper
        include Copilot::Mcp::EnterpriseRegistryShared

        sig { params(organization: ::Copilot::Organization, user: ::User, additional_params: T.nilable(Copilot::Types::AdditionalParameters)).void }
        def initialize(organization:, user:, additional_params: nil)
          @organization = organization
          @user = user
          @additional_params = additional_params
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

          can_edit_mcp_registry = true
          can_edit_mcp_registry_access = true
          can_see_mcp_registry = @organization.feature_flag_enabled_or_raise?(:copilot_mcp_registry) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))
          allowlist_info = T.let(nil, T.nilable(Copilot::Types::McpAllowlistInfo))

          if copilot_business
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            # Only restrict editing if the enterprise has explicitly assigned an allowlist to this org.
            # When mcp_no_policy? (orgs decide), editing is always allowed — set a default allowlist_info
            # so the cached value is passed through to mcp_registry_enterprise_policy_payload and the
            # external API call is truly skipped. When the enterprise has an explicit policy, fetch the
            # allowlist assignment once and cache it to avoid a duplicate call.
            if copilot_business.mcp_no_policy?
              allowlist_info = { has_assigned_allowlist: false, assigned_allowlist_name: nil }
            else
              allowlist_info = mcp_registry_assigned_allowlist(copilot_business)
              has_assigned_allowlist = allowlist_info[:has_assigned_allowlist]
              # If has_assigned_allowlist is nil (API error), treat as false to allow editing as fallback
              can_edit_mcp_registry = (has_assigned_allowlist != true)
              can_edit_mcp_registry_access = (has_assigned_allowlist != true)
            end
          end

          # Compute overage policies once to avoid multiple API calls
          billing_builder = BillingPayloadBuilder.new(organization: @organization)
          overage_policies = billing_builder.get_overage_policies

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            blackbird_external_indexing: policy_hash(
              Copilot::Policies::BlackbirdExternalIndexing,
              helptext: "Learn more about Semantic search external indexing",
              description: "If enabled, members of this organization will have access to upload non-GitHub repositories for Semantic Indexing.",
            ),
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            show_policies_when_copilot_disabled: show_policies_when_copilot_disabled,
            editor_chat: policy_hash(
              Copilot::Policies::EditorChat,
              helptext: "Learn more about Copilot in your editor.",
              description: "If enabled, members of this organization will have access to #{Copilot::COPILOT_CHAT_IN_IDE}.",
            ),
            mobile_chat: policy_hash(
              Copilot::Policies::MobileChat,
              helptext: "Learn more about Copilot in GitHub Mobile.",
              description: "If enabled, members of this organization will have access to #{Copilot::COPILOT_CHAT_IN_MOBILE}.",
            ),
            memory: policy_hash(
              Copilot::Policies::Memory,
              helptext: "Learn more about Copilot Memory.",
              description: Copilot::Policies::Memory.organization_setting_payload_description(
                user_scoped_memories: memory_user_scoped_enabled?,
              ),
            ),
            spaces: policy_hash(
              Copilot::Policies::Spaces,
              helptext: "Learn more about Copilot Spaces.",
              description: "If enabled, members of this organization can view and create Copilot Spaces. When disabled, users cannot view or create any Copilot Spaces.",
            ),
            spaces_individual_access: policy_hash(
              Copilot::Policies::SpacesIndividualAccess,
              helptext: "Learn more about Copilot Spaces.",
              description: "If enabled, organization members can create individually owned Copilot Spaces. When disabled, users cannot create individual spaces.",
            ),
            spaces_individual_sharing: policy_hash(
              Copilot::Policies::SpacesIndividualSharing,
              helptext: "Learn more about Copilot Spaces.",
              description: "If enabled, organization members can share individually owned Copilot Spaces. When disabled, users cannot share individual spaces with others.",
            ),
            editor_preview_features: policy_hash(
              Copilot::Policies::EditorPreviewFeatures,
              helptext: nil,
              description: "If enabled, members of this organization will have access to editor preview features, including MCP servers.",
            ),
            agent_mode: policy_hash(
              Copilot::Policies::AgentMode,
              helptext: "Learn more about #{Copilot::Policies::AgentMode.display_name}.",
              description: "If enabled, members of this organization may use Agent Mode within their IDE to interact with Copilot for the purpose of reasoning through requests, planning tasks, and making changes to the codebase.",
            ),
            agent_mode_auto_approve: policy_hash(
              Copilot::Policies::AgentModeAutoApprove,
              helptext: nil,
              description: "If enabled, members of this organization may use #{Copilot::Policies::AgentModeAutoApprove.display_name} (currently supported by JetBrains plugin only).",
            ),
            snippy: policy_hash(
              Copilot::Policies::Snippy,
              helptext: nil,
              description: "Copilot can allow or block suggestions matching public code.",
              menu_items: Copilot::Policies::Menus::ALLOW_OR_BLOCK
            ),
            duplicate_detection_filter: duplicate_detection_filter_policy_hash,
            cli: policy_hash(
              Copilot::Policies::Cli,
              helptext: "Learn more about Copilot CLI.",
              description: "If enabled, members of this organization can use GitHub Copilot CLI as an assistant in the terminal."
            ),
            desktop: policy_hash(
              Copilot::Policies::Desktop,
              helptext: "Learn more about Copilot in GitHub Desktop.",
              description: "If enabled, members of this organization will get Copilot assistance in GitHub Desktop.",
            ),
            copilot_for_dotcom: legacy_policy_hash(Copilot::Policies::Dotcom),
            bing_github_chat: policy_hash(
              Copilot::Policies::Bing,
              description: "Copilot can answer questions about new trends and give improved answers, via Bing.",
              helptext: "See the Microsoft Privacy Statement.",
            ),
            model_native_search: policy_hash(
              Copilot::Policies::ModelNativeSearch,
              description: "Copilot can answer questions using a model's built-in search capabilities.",
              helptext: nil,
            ),
            restrict_to_azure: policy_hash(
              Copilot::Policies::RestrictToAzure,
              helptext: nil,
              description: Copilot::Policies::RestrictToAzure.description,
            ),
            restrict_to_data_residency: policy_hash(
              Copilot::Policies::RestrictToDataResidency,
              helptext: nil,
              description: Copilot::Policies::RestrictToDataResidency.description,
            ),
            restrict_to_fedramp: policy_hash(
              Copilot::Policies::RestrictToFedramp,
              helptext: nil,
              description: Copilot::Policies::RestrictToFedramp.description,
            ),
            client_byok: policy_hash(
              Copilot::Policies::ClientByok,
              helptext: "Learn more.",
              description: Copilot::Policies::ClientByok.description,
            ),
            copilot_user_feedback_opt_in: opt_in_policy_hash(Copilot::Policies::UserFeedback),
            copilot_beta_features_opt_in: opt_in_policy_hash(Copilot::Policies::DotcomBetaFeatures),
            copilot_extensions: legacy_policy_hash(Copilot::Policies::Extensions),
            private_telemetry: legacy_policy_hash(Copilot::Policies::PrivateTelemetry),
            mcp:  policy_hash(
              Copilot::Policies::Mcp,
              helptext: "See MCP docs for Copilot Chat and Copilot cloud agent.",
              description: "If enabled, users can configure Model Context Protocol (MCP) servers (including third-party servers) for Copilot in all Copilot editors and Copilot cloud agent.",
            ),
            mcp_registry: {
              manages: "copilot_mcp_registry",
              displayname: Copilot::COPILOT_MCP_REGISTRY,
              description: nil,
              visible: can_see_mcp_registry,
              configurable: can_edit_mcp_registry,
              options: nil,
              helptext: nil,
              helpurl: nil,
              preview: true,
              submitPath: mcp_registry_submit_path,
              mcpRegistryUrl: @organization.mcp_registry_url,
              mcpRegistryId: @organization.mcp_registry_id,
            },
            mcp_registry_access: {
              manages: "copilot_mcp_registry_access",
              displayname: Copilot::COPILOT_MCP_REGISTRY_ACCESS,
              description: "Control which MCP servers are allowed based on your registry configuration.",
              visible: can_see_mcp_registry,
              configurable: can_edit_mcp_registry_access,
              options: make_menu_options([
                Copilot::Policies::MenuItems::McpRegistryAccess::AllowAll,
                Copilot::Policies::MenuItems::McpRegistryAccess::RegistryOnly,
              ]),
              helptext: "View docs on MCP registry allow lists.",
              helpurl: "https://gh.io/mcp-registry-allow-lists",
              preview: true,
              submitPath: mcp_registry_submit_path,
              mcpRegistryUrl: nil,
              mcpRegistryId: @organization.mcp_registry_id,
            },
            mcp_registry_enterprise: mcp_registry_enterprise_policy_payload(copilot_business, allowlist_info),
            copilot_usage_metrics_policy: policy_hash(
              Copilot::Policies::MetricsApi,
              description: "If enabled, organizations administrators can query the #{Copilot::COPILOT_METRICS_API_NAME} for insights into Copilot usage.",
              helptext: "Learn more about the Copilot Metrics API.",
            ),
            code_review:  legacy_policy_hash(Copilot::Policies::CodeReview),
            code_review_beta_features: opt_in_policy_hash(Copilot::Policies::CodeReviewBetaFeatures),
            ccr_direct_org_billing: billing_builder.ccr_direct_org_billing_policy_hash(overage_policies),
            cca_direct_org_billing: billing_builder.cca_direct_org_billing_policy_hash(overage_policies),
            cli_direct_org_billing: billing_builder.cli_direct_org_billing_policy_hash(overage_policies),
            cli_remote_control: policy_hash(
              Copilot::Policies::CliRemoteControl,
              helptext: "Learn more about Copilot CLI Remote Control.",
              description: "If enabled, CLI sessions can be viewed and steered from github.com and GitHub Mobile.",
            ),
            cli_cloud_session_storage: cloud_session_storage_policy_hash,
            cca_agentic_github_apps: policy_hash(
              Copilot::Policies::CcaAgenticGitHubApps,
              helptext: nil,
              description: "If enabled, organizations can use agentic features provided by GitHub Apps.",
            ),
            swe_agent:  policy_hash(
              Copilot::Policies::CodingAgent,
              helptext: "Learn more.",
              description: "If enabled, users assigned a Copilot license from this organization will have access to #{Copilot::COPILOT_SWE_AGENT} in repositories where it is enabled. This feature may use models which are not enabled on your Models settings page.",
            ),
            swe_agent_member_requests: get_member_request_data(MemberFeatureRequest::Feature::CopilotCodingAgent),
            spark: policy_hash(
              Copilot::Policies::Spark,
              helptext: "Learn more about #{Copilot::SPARK_NAME}.",
              description: "If enabled, members of your enterprise will have access to #{Copilot::SPARK_NAME}.",
            ),
            spark_force_org: opt_in_policy_hash(Copilot::Policies::SparkForceOrg),
            insights: insights_policy_hash(
              Copilot::Policies::Insights,
              helptext: "Learn more about the Copilot Usage API.",
              description: "If enabled, organization admins and authorized users can access the Copilot Usage API.",
            ),
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            },
            overages: overage_policies,
            generated_commit_message: policy_hash(
              Copilot::Policies::GeneratedCommitMessage,
              helptext: "Learn more about #{Copilot::COPILOT_GENERATED_COMMIT_MESSAGE}.",
              description: "If enabled, Copilot will suggest commit messages for changes made on GitHub.com.",
            ),
            member_feature_request: {
              request_completed: @additional_params&.fetch(:member_feature_request_completed, false) == "true",
              feature_name: @additional_params&.fetch(:member_feature_request_feature_name, nil)&.to_s,
            },
          }
        end

        private

        sig { returns(T::Boolean) }
        def memory_user_scoped_enabled?
          @organization.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false) ||
            @organization.business&.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false) ||
            @user.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false)
        end

        sig { returns(String) }
        def mcp_registry_submit_path
          url_helpers = Rails.application.routes.url_helpers
          return "" unless url_helpers.respond_to?(:settings_org_copilot_mcp_registry_url_create_or_update_path)

          url_helpers.settings_org_copilot_mcp_registry_url_create_or_update_path(@organization)
        end

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

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: T.nilable(String), description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
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
            warning: nil,
          }
        end

        # Duplicate Detection Filter treats unconfigured as enabled for both the org's own value
        # and any inherited business value.
        sig { returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def duplicate_detection_filter_policy_hash
          policy_class = Copilot::Policies::DuplicateDetectionFilter
          value = policy_class.value(@organization)
          value = "enabled" if policy_class.unconfigured?(@organization)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            helptext: nil,
            description: "Control whether the Duplicate Detection filter is enabled for Copilot within your organization.",
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(value),
            preview: policy_class.preview?(@organization),
            warning: nil,
          }
        end

        sig { returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def cloud_session_storage_policy_hash
          policy_class = Copilot::Policies::CliCloudSessionStorage
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            helptext: "Learn more about cloud session storage.",
            description: policy_class.organization_setting_payload_description,
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(
              policy_class.combined_value(@organization),
              Copilot::Policies::Menus::CLOUD_SESSION_STORAGE,
            ),
            preview: policy_class.preview?(@organization),
            warning: nil,
          }
        end

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: T.nilable(String), description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadNewAspect) }
        def insights_policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            helptext: helptext,
            description: description,
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(@organization.insights_enabled? ? Copilot::Policies::MenuItems::GeneralPolicies::Enabled.value : Copilot::Policies::MenuItems::GeneralPolicies::Disabled.value, menu_items),
            preview: policy_class.preview?(@organization),
            warning: nil,
          }
        end

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(Copilot::Types::PoliciesIndexPayloadAspect) }
        def legacy_policy_hash(policy_class, menu_items: Copilot::Policies::Menus::DEFAULT)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            options: make_general_menu_options(policy_class.value(@organization), menu_items),
          }
        end

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy).returns(Copilot::Types::PoliciesIndexPayloadOptInAspect) }
        def opt_in_policy_hash(policy_class)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            enabled: policy_class.enabled?(@organization)
          }
        end

        sig do
          params(feature: MemberFeatureRequest::Feature).returns(
            T.nilable(Copilot::Types::MemberRequestDataType)
          )
        end
        def get_member_request_data(feature)
          org = @organization.organization_object
          requests_count = MemberFeatureRequest.total_for_feature(org, feature)
          return nil if requests_count.zero?
          return nil if feature.supported?(request_entity: org)

          requesting_users = MemberFeatureRequest.requested_member_requests(org)
            .where(feature: feature)
            .includes(:requester)
            .order(created_at: :desc)
            .limit(5)
            .map(&:requester)
            .compact

          {
            should_render: true,
            requests_count: requests_count,
            requesting_users: requesting_users.map do |user|
              {
                id: user.id,
                display_login: user.display_login,
                avatar_url: user.primary_avatar_url,
              }
            end,
            feature_name: feature.name,
          }
        end

        sig { returns(T::Boolean) }
        def show_policies_when_copilot_disabled
          !(@organization.has_copilot_for_business? || @organization.has_trial?) &&
            @organization.can_view_settings_page_with_copilot_disabled?
        end

        sig do
          params(
            copilot_business: T.nilable(Copilot::Business),
            cached_allowlist_info: T.nilable(Copilot::Types::McpAllowlistInfo),
          ).returns(Copilot::Types::McpRegistryEnterprisePolicyPayload)
        end
        def mcp_registry_enterprise_policy_payload(copilot_business, cached_allowlist_info = nil)
          if mcp_registry_enterprise_policy_visible?(@user, copilot_business)
            cb = T.must(copilot_business)
            {
              visible: true,
              local_server_block: mcp_registry_local_server_block(cb),
              can_edit_mcp_policy: cb.mcp_no_policy?,
              mcp_policy_label: Copilot::Policies::Mcp.value(@organization).titleize,
              registry_type_text: mcp_registry_type_text(cb),
              # cached_allowlist_info is always set by the call method when copilot_business is present,
              # so the fallback only fires when this method is called directly without a cached value.
              **(cached_allowlist_info || mcp_registry_assigned_allowlist(cb))
            }
          else
            {
              visible: false,
              local_server_block: nil,
              can_edit_mcp_policy: true,
              mcp_policy_label: nil,
              registry_type_text: nil,
              has_assigned_allowlist: false,
              assigned_allowlist_name: nil,
            }
          end
        end

        sig { params(copilot_business: Copilot::Business).returns(T.nilable(String)) }
        def mcp_registry_type_text(copilot_business)
          registry = copilot_business.mcp_registry
          if registry&.registry_type_github?
            "GitHub Registry"
          elsif registry&.registry_type_external?
            "External Registry"
          else
            nil
          end
        end

        sig { params(copilot_business: Copilot::Business).returns(T.nilable(T::Boolean)) }
        def mcp_registry_local_server_block(copilot_business)
          settings = ::McpRegistry::EnterpriseSettingsClient.get_settings(
            enterprise_id: copilot_business.id,
            token: mcp_registry_token(@user),
          )
          settings["block_local_servers"] == true
        rescue StandardError => e
          Rails.logger.error("Failed to fetch enterprise MCP settings: #{e.message}")
          nil
        end

        sig { params(copilot_business: Copilot::Business).returns(Copilot::Types::McpAllowlistInfo) }
        def mcp_registry_assigned_allowlist(copilot_business)
          assignment = ::McpRegistry::EnterpriseAllowlistClient.get_allowlist_assignment(
            enterprise_id: copilot_business.id.to_s,
            namespace_type: "org",
            namespace_id: @organization.id.to_s,
            token: mcp_registry_token(@user),
          )
          if assignment
            {
              has_assigned_allowlist: true,
              assigned_allowlist_name: assignment["allowlist"]["name"],
            }
          else
            {
              has_assigned_allowlist: false,
              assigned_allowlist_name: nil,
            }
          end
        rescue StandardError => e
          Rails.logger.error("Failed to fetch enterprise allowlist assignment: #{e.message}")
          {
            has_assigned_allowlist: nil,
            assigned_allowlist_name: nil,
          }
        end
      end
    end
  end
end
