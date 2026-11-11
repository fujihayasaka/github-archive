# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class Payload < ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper

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

          if copilot_business
            # if the business has an explicit policy, this user cannot edit it. So lets check for it.
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            can_edit_mcp_registry = copilot_business.mcp_no_policy?
            can_edit_mcp_registry_access = copilot_business.mcp_no_policy?
          end

          # Compute overage policies once to avoid multiple API calls
          overage_policies = get_overage_policies

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
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
            cli: legacy_policy_hash(Copilot::Policies::Cli),
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
            restrict_to_azure: policy_hash(
              Copilot::Policies::RestrictToAzure,
              helptext: nil,
              description: Copilot::Policies::RestrictToAzure.description,
            ),
            copilot_user_feedback_opt_in: opt_in_policy_hash(Copilot::Policies::UserFeedback),
            copilot_beta_features_opt_in: opt_in_policy_hash(Copilot::Policies::DotcomBetaFeatures),
            copilot_extensions: legacy_policy_hash(Copilot::Policies::Extensions),
            private_telemetry: legacy_policy_hash(Copilot::Policies::PrivateTelemetry),
            mcp:  policy_hash(
              Copilot::Policies::Mcp,
              helptext: "See MCP docs for Copilot Chat and Coding Agent.",
              description: "If enabled, users can configure Model Context Protocol (MCP) servers (including third-party servers) for Copilot in all Copilot editors and Coding Agent.",
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
              preview: true,
              submitPath: Rails.application.routes.url_helpers.settings_org_copilot_mcp_registry_url_create_or_update_path(@organization),
              mcpRegistryUrl: nil,
              mcpRegistryId: @organization.mcp_registry_id,
              isGA: @organization.feature_flag_enabled?(:copilot_mcp_registry_ga, default: false),
            },
            copilot_usage_metrics_policy: policy_hash(
              Copilot::Policies::MetricsApi,
              description: "If enabled, organizations administrators can query the #{Copilot::COPILOT_METRICS_API_NAME} for insights into Copilot usage.",
              helptext: "Learn more about the Copilot Metrics API.",
            ),
            code_review:  legacy_policy_hash(Copilot::Policies::CodeReview),
            code_review_beta_features: opt_in_policy_hash(Copilot::Policies::CodeReviewBetaFeatures),
            ccr_direct_org_billing: ccr_direct_org_billing_policy_hash(overage_policies),
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
            loops: policy_hash(
              Copilot::Policies::Loops,
              helptext: "Learn more about #{Copilot::Policies::Loops.display_name}.",
              description: "If enabled, members of your organization will have access to #{Copilot::Policies::Loops.display_name}.",
            ),
            insights: policy_hash(
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

        sig { params(overage_policies: Copilot::Types::BillingOveragesPayload).returns(Copilot::Types::CcrDirectOrgBillingPolicyPayload) }
        def ccr_direct_org_billing_policy_hash(overage_policies)
          policy_class = Copilot::Policies::CcrDirectOrgBilling
          base_hash = opt_in_policy_hash(policy_class)

          # Get PRU (Premium Request Usage) status from the overage policies
          pru_enabled = overage_policies[:copilot_premium_request][:value]

          base_hash.merge(pru_enabled: pru_enabled)
        end


        sig { returns(Copilot::Types::BillingOveragesPayload) }
        def get_overage_policies
          policies = {
            copilot_premium_request: { type: "sku", name: "copilot_premium_request" },
            coding_agent_premium_request: { type: "sku", name: "coding_agent_premium_request" },
            spark: { type: "product", name: "spark" }
          }

          delegate_billing = @organization.business.present?
          customer = nil

          if delegate_billing
            customer = @organization.business&.customer
          else
            customer = @organization.customer
          end

          responses = {}
          policies.each do |key, details|
            if customer.present?
              responses[key] = billing_platform_client.get_overage_policy(
                customer_id: customer.id,
                overage_policy_type: details[:type],
                name: details[:name],
                is_for_business: true
              )
            end
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
            coding_agent_premium_request: { value: false, visible: !has_error },
            spark: { value: false, visible: !has_error }
          }

          unless has_error
            policies.keys.each do |policy_key|
              response = responses[policy_key]
              if !response.is_a?(::Billing::Platform::Api::Error) && response.present? && response[:overagePolicy].present? && response[:overagePolicy][:enabled]
                result[policy_key][:value] = true
              end
            end
          end

          # set this value to the copilot_premium_request value for backwards compatibility as github-ui will check for this before both parts are rolled out
          result[:value] = result[:copilot_premium_request][:value]
          result
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

        sig { returns(::Billing::Platform::Api::Client) }
        def billing_platform_client
          ::Billing::Platform::Api::Client.new
        end
      end
    end
  end
end
