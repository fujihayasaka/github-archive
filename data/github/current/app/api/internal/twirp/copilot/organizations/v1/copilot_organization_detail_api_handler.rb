# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-organizations"

module Api::Internal::Twirp::Copilot
  module Organizations
    module V1
      # Handler for the MonolithTwirp::Copilot::Organizations::V1::CopilotOrganizationDetailAPIService
      class CopilotOrganizationDetailAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[copilot_usage_service copilot_api sweagentd copilot_limiter chat_integrations]
        handles_service MonolithTwirp::Copilot::Organizations::V1::CopilotOrganizationDetailAPIService

        # Public: Implementation of the GetCopilotOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def get_copilot_organization(req, env)
          # we need an id or and analytics_tracking_id
          unless (req.id.present? && req.id.nonzero?) || req.analytics_tracking_id.present?
            return Twirp::Error.invalid_argument("must be provided", argument: "id or analytics_tracking_id")
          end

          organization = load_organization(req)
          return Twirp::Error.not_found("Organization ID '#{req.id}' not found.") unless organization

          copilot_organization = Copilot::Organization.new(organization)
          load_single_response(copilot_organization)
        end

        # Public: Implementation of the GetCopilotOrganizationsByAnalyticTrackingIds Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def get_copilot_organizations_by_analytic_tracking_ids(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "analytics_tracking_ids") unless req.analytics_tracking_ids.present?
          {
            organization_details: load_multiple_responses(req.analytics_tracking_ids.map(&:to_s)),
          }
        end

        private

        CopilotOrganizationMinimalDetails = T.type_alias do
          {
            analytics_tracking_id: T.nilable(String),
            are_metrics_enabled: T.nilable(T::Boolean),
            business_id: T.nilable(Integer),
            display_login: T.nilable(String),
            id: T.nilable(Integer),
            use_token_based_billing: T.nilable(T::Boolean),
          }
        end

        GetCopilotOrganizationsByAnalyticTrackingIdsResponse = T.type_alias do
          {
            organization_details: T.nilable(CopilotOrganizationMinimalDetails)
          }
        end

        SeatBreakdown = T.type_alias do
          {
            seats_assigned: T.nilable(Integer),
            seats_billed: T.nilable(Integer),
            seats_pending: T.nilable(Integer)
          }
        end

        ModelPoliciesHash = T.type_alias do
          {
            model_policy: T::Hash[Symbol, Integer],
          }
        end

        CopilotOrganizationDetails = T.type_alias do
          {
            analytics_tracking_id: T.nilable(String),
            are_metrics_enabled: T.nilable(T::Boolean),
            business_id: T.nilable(Integer),
            chat_enabled: T.nilable(T.any(Symbol, Integer)),
            copilot_billing_type: T.nilable(String),
            copilot_enabled: T.nilable(T.any(Symbol, Integer)),
            id: T.nilable(Integer),
            legacy_model_policies: T.nilable(ModelPoliciesHash),
            mobile_chat: T.nilable(T.any(Symbol, Integer)),
            model_policies: T.nilable(ModelPoliciesHash),
            on_free_trial: T.nilable(T::Boolean),
            org_member_count: T.nilable(Integer),
            public_code_suggestions: T.nilable(T.any(Symbol, Integer)),
            seat_break_down: T.nilable(SeatBreakdown),
            seat_management: T.nilable(T.any(Symbol, Integer)),
            swe_agent_setting: T.nilable(T.any(Symbol, Integer)),
            cca_direct_org_billing_enabled: T.nilable(T::Boolean),
            cli_direct_org_billing_enabled: T.nilable(T::Boolean),
            ccr_direct_org_billing_enabled: T.nilable(T::Boolean),
            cli_setting: T.nilable(T.any(Symbol, Integer)),
            copilot_plan: T.nilable(T.any(Symbol, Integer)),
            duplicate_detection_filter: T.nilable(T.any(Symbol, Integer)),
            cli_remote_control_setting: T.nilable(T.any(Symbol, Integer)),
            direct_org_billing_eligible: T.nilable(T::Boolean),
            use_token_based_billing: T.nilable(T::Boolean),
          }
        end

        GetCopilotOrganizationResponse = T.type_alias do
          {
            organization_details: T.nilable(CopilotOrganizationDetails)
          }
        end

        sig do
          params(
            copilot_organization: Copilot::Organization
          ).
          returns(
            GetCopilotOrganizationResponse
          )
        end
        def load_single_response(copilot_organization)
          seat_breakdown = load_seat_break_down(copilot_organization)

          {
            organization_details: {
              analytics_tracking_id: copilot_organization.analytics_tracking_id,
              are_metrics_enabled: copilot_organization.telemetry_aggregation_enabled?,
              business_id: copilot_organization.copilot_business&.id,
              chat_enabled: load_copilot_editor_chat_setting(copilot_organization),
              copilot_billing_type: copilot_organization.copilot_billing_type,
              copilot_enabled: load_copilot_enabled_setting(copilot_organization),
              id: copilot_organization.id,
              legacy_model_policies: load_legacy_model_policies(copilot_organization),
              mobile_chat: load_copilot_mobile_chat_setting(copilot_organization),
              model_policies: load_model_policies(copilot_organization),
              on_free_trial: copilot_organization.on_free_trial?,
              org_member_count: copilot_organization.organization_object.members_count,
              public_code_suggestions: load_copilot_snippy_setting(copilot_organization),
              seat_break_down: seat_breakdown,
              seat_management: nil,
              swe_agent_setting: load_swe_agent_setting(copilot_organization),
              cca_direct_org_billing_enabled: load_cca_direct_org_billing_enabled(copilot_organization),
              cli_direct_org_billing_enabled: load_cli_direct_org_billing_enabled(copilot_organization),
              ccr_direct_org_billing_enabled: load_ccr_direct_org_billing_enabled(copilot_organization),
              cli_setting: load_cli_setting(copilot_organization),
              copilot_plan: load_copilot_plan(copilot_organization),
              duplicate_detection_filter: load_copilot_duplicate_detection_filter_setting(copilot_organization),
              cli_remote_control_setting: load_cli_remote_control_setting(copilot_organization),
              direct_org_billing_eligible: load_direct_org_billing_eligible(copilot_organization, seat_breakdown),
              use_token_based_billing: copilot_organization.use_token_based_billing?,
            }
          }
        end

        sig do
          params(
            analytic_tracking_ids: T::Array[String]
          ).
          returns(
            T::Array[CopilotOrganizationMinimalDetails]
          )
        end
        def load_multiple_responses(analytic_tracking_ids)
          ::Organization.where(analytics_tracking_id: analytic_tracking_ids).inject([]) do |memo, organization|
            next memo if organization.nil?
            copilot_org = Copilot::Organization.new(organization)
            org_hash = {
              analytics_tracking_id: organization.analytics_tracking_id,
              are_metrics_enabled: copilot_org.telemetry_aggregation_enabled?,
              business_id: organization.business&.id,
              display_login: organization.display_login,
              id: organization.id,
              use_token_based_billing: copilot_org.use_token_based_billing?,
            }

            if organization.feature_flag_enabled?(:copilot_include_customer_in_org_detail_handler, default: false)
              org_hash[:customer_id] = copilot_org.customer_for&.id
            end

            memo << org_hash
            memo
          end
        end

        sig { params(copilot_organization: Copilot::Organization).returns(SeatBreakdown) }
        def load_seat_break_down(copilot_organization)
          break_down = Copilot::Organizations::SeatManagement::SeatBreakdown.new(copilot_organization.organization_object)
          {
            seats_assigned: break_down.seats_assigned,
            seats_billed: break_down.seats_billed,
            seats_pending: break_down.seats_pending,
          }
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_editor_chat_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_ENABLED if copilot_organization.chat_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_DISABLED if copilot_organization.chat_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_NO_POLICY if copilot_organization.no_chat_policy?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_UNCONFIGURED unless copilot_organization.chat_enabled_configured?
          MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_mobile_chat_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_ENABLED if copilot_organization.mobile_chat_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_DISABLED if copilot_organization.mobile_chat_disabled?
          MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_enabled_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_DISABLED if copilot_organization.copilot_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_ENABLED if copilot_organization.copilot_enabled?
          MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_snippy_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_UNCONFIGURED unless copilot_organization.public_code_suggestions_configured?
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_ALLOWED if copilot_organization.allow_public_code_suggestions?
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_BLOCKED if copilot_organization.block_public_code_suggestions?
          MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(T.any(Symbol, Integer))) }
        def load_copilot_duplicate_detection_filter_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_ENABLED if Copilot::Policies::DuplicateDetectionFilter.enabled?(copilot_organization) || Copilot::Policies::DuplicateDetectionFilter.unconfigured?(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_DISABLED if Copilot::Policies::DuplicateDetectionFilter.disabled?(copilot_organization)
          MonolithTwirp::Copilot::Organizations::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(T.any(Symbol, Integer))) }
        def load_swe_agent_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::SWEAgent::SWE_AGENT_ENABLED if copilot_organization.swe_agent_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::SWEAgent::SWE_AGENT_DISABLED if copilot_organization.swe_agent_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::SWEAgent::SWE_AGENT_UNCONFIGURED if copilot_organization.swe_agent_unconfigured?
          MonolithTwirp::Copilot::Organizations::V1::SWEAgent::SWE_AGENT_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T::Boolean) }
        def load_cca_direct_org_billing_enabled(copilot_organization)
          return true if Copilot::Policies::CcaDirectOrgBilling.enabled?(copilot_organization)
          false
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(T.any(Symbol, Integer))) }
        def load_cli_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::CLI::CLI_ENABLED if copilot_organization.cli_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::CLI::CLI_DISABLED if copilot_organization.cli_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::CLI::CLI_UNCONFIGURED if copilot_organization.cli_unconfigured?
          MonolithTwirp::Copilot::Organizations::V1::CLI::CLI_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(T.any(Symbol, Integer))) }
        def load_cli_remote_control_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_ENABLED if copilot_organization.cli_remote_control_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_DISABLED if copilot_organization.cli_remote_control_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_UNCONFIGURED if copilot_organization.cli_remote_control_unconfigured?
          MonolithTwirp::Copilot::Organizations::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T::Boolean) }
        def load_cli_direct_org_billing_enabled(copilot_organization)
          return true if Copilot::Policies::CliDirectOrgBilling.enabled?(copilot_organization)
          false
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T::Boolean) }
        def load_ccr_direct_org_billing_enabled(copilot_organization)
          return true if Copilot::Policies::CcrDirectOrgBilling.enabled?(copilot_organization)
          false
        end

        sig { params(copilot_organization: Copilot::Organization, seat_breakdown: SeatBreakdown).returns(T::Boolean) }
        def load_direct_org_billing_eligible(copilot_organization, seat_breakdown)
          return true unless copilot_organization.feature_flag_enabled?(:copilot_api_s2s_require_cbce, default: false)

          # If this org already has billed seats, no need to check the enterprise
          return true if seat_breakdown[:seats_billed].to_i > 0

          copilot_organization.has_copilot_seats_for_direct_billing?
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(Integer)) }
        def load_copilot_plan(copilot_organization)
          # if the org doesn't have copilot enabled, but has CCA or CLI direct org billing enabled,
          # we want to send over Copilot Business plan so they get default copilot behaviors in CAPI
          direct_org_billing_enabled = !copilot_organization.has_configured_copilot_plan? && copilot_organization.has_copilot_direct_org_billing_enabled?

          return MonolithTwirp::Copilot::Organizations::V1::CopilotPlan::COPILOT_PLAN_ENTERPRISE if copilot_organization.copilot_plan_enterprise? || copilot_organization.on_free_copilot_enterprise_trial?
          return MonolithTwirp::Copilot::Organizations::V1::CopilotPlan::COPILOT_PLAN_BUSINESS if direct_org_billing_enabled
          return MonolithTwirp::Copilot::Organizations::V1::CopilotPlan::COPILOT_PLAN_INVALID if !copilot_organization.has_configured_copilot_plan?

          MonolithTwirp::Copilot::Organizations::V1::CopilotPlan::COPILOT_PLAN_BUSINESS
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(ModelPoliciesHash)) }
        def load_legacy_model_policies(copilot_organization)
          policy_map = {}

          Copilot::Policies::MODELS.each do |policy|
            next unless policy.is_a?(Copilot::Policies::Concerns::Twirpable)
            next unless policy.available_for?(copilot_organization)

            model_key = policy.config_name.to_sym
            # GPT 4.1 is currently our base model and should always be enabled unless they're one of the FSI customers.
            db_value = if policy == Copilot::Policies::Models::Ofo && !copilot_organization.feature_flag_enabled?(:copilot_api_force_legacy_base_chat_model, default: false)
              "enabled"
            else
              policy.value(copilot_organization)
            end
            policy_map[model_key] = model_policy_to_twirp(db_value)
          end

          return nil if policy_map.empty?

          { model_policy: policy_map }
        end

        sig { params(copilot_organization: Copilot::Organization).returns(T.nilable(ModelPoliciesHash)) }
        def load_model_policies(copilot_organization)
          policy_map = {}

          all_models = Copilot::ModelsRegistryCache.all_cached
          available_model_keys = copilot_organization.registry_models.map(&:model_key).to_set
          all_models.each do |model|
            model_key = model.model_key.to_sym
            db_value = if available_model_keys.include?(model.model_key)
              copilot_organization.model_policy(model.model_key)
            else
              "unconfigured"
            end

            policy_map[model_key] = model_policy_to_twirp(db_value)
          end

          return nil if policy_map.empty?

          { model_policy: policy_map }
        end

        sig { params(db_value: String).returns(Integer) }
        def model_policy_to_twirp(db_value)
          case db_value
          when "enabled"
            MonolithTwirp::Copilot::Organizations::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_ENABLED_SETTING
          when "disabled"
            MonolithTwirp::Copilot::Organizations::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_DISABLED_SETTING
          when "unconfigured"
            MonolithTwirp::Copilot::Organizations::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_UNCONFIGURED_SETTING
          when "no_policy"
            MonolithTwirp::Copilot::Organizations::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_NO_POLICY_SETTING
          else
            MonolithTwirp::Copilot::Organizations::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_INVALID
          end
        end

        sig { params(req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest).returns(T.nilable(::Organization)) }
        def load_organization(req)
          if req.id.present? && req.id.nonzero?
            ::Organization.find_by(id: req.id)
          elsif req.analytics_tracking_id.present?
            ::Organization.find_by(analytics_tracking_id: req.analytics_tracking_id)
          else
            nil
          end
        end
      end
    end
  end
end
