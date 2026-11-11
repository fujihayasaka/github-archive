# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CliPolicyDetails
      EntityValue = T.type_alias { T.any(String, Integer) }
      Entity = T.type_alias { T::Hash[Symbol, EntityValue] }
      DetailValue = T.type_alias { T.any(String, T::Array[Entity]) }
      Detail = T.type_alias { T::Hash[Symbol, DetailValue] }
      Details = T.type_alias { T::Hash[Symbol, Detail] }

      class << self
        sig do
          params(
            copilot_user: Copilot::User,
            all_policies: Copilot::Users::Policies::CopilotAllPolicies,
            cli_remote_control_value: String,
            cloud_session_storage_value: T.nilable(String),
          ).returns(Details)
        end
        def call(copilot_user:, all_policies:, cli_remote_control_value:, cloud_session_storage_value:)
          details = T.let({}, Details)

          if cloud_session_storage_value == "disabled"
            reason = cli_cloud_session_storage_policy_reason(copilot_user, all_policies, cloud_session_storage_value)
            details[:cli_cloud_session_storage] = policy_detail(
              all_policies: all_policies,
              policy: :cli_cloud_session_storage,
              effective_value: cloud_session_storage_value,
              reason: reason,
              required_fix: cli_cloud_session_storage_required_fix(reason),
            )
          end

          if cli_remote_control_value == "disabled"
            reason = cli_remote_control_policy_reason(copilot_user, all_policies, cli_remote_control_value)
            details[:cli_remote_control] = policy_detail(
              all_policies: all_policies,
              policy: :cli_remote_control,
              effective_value: cli_remote_control_value,
              reason: reason,
              required_fix: cli_remote_control_required_fix(reason),
              blocking_policy: cli_remote_control_blocking_policy(copilot_user, all_policies),
            )
          end

          details
        end

        private

        sig do
          params(
            all_policies: Copilot::Users::Policies::CopilotAllPolicies,
            policy: Symbol,
            effective_value: String,
            reason: String,
            required_fix: String,
            blocking_policy: T.nilable(Symbol),
          ).returns(Detail)
        end
        def policy_detail(all_policies:, policy:, effective_value:, reason:, required_fix:, blocking_policy: nil)
          policy_for_blocking_entities = blocking_policy || policy
          entities = policy_entities(all_policies, policy)
          blocking_policy_entities =
            if policy_for_blocking_entities == policy
              entities
            else
              policy_entities(all_policies, policy_for_blocking_entities)
            end
          blocking_entities = policy_blocking_entities(blocking_policy_entities, reason)
          {
            policy: policy.to_s,
            effective_value: effective_value,
            reason: reason,
            required_fix: required_fix,
            blocking_policy: policy_for_blocking_entities.to_s,
            blocking_entities: blocking_entities,
            non_blocking_entities: entities - blocking_entities,
          }
        end

        sig do
          params(
            entities: T::Array[Entity],
            reason: String,
          ).returns(T::Array[Entity])
        end
        def policy_blocking_entities(entities, reason)
          case reason
          when "business_policy_disabled"
            entities.select { |entity| entity[:type] == "business" && entity[:value] == "disabled" }
          when "organization_policy_disabled"
            entities.select { |entity| entity[:type] == "organization" && entity[:value] == "disabled" }
          when "cloud_session_storage_policy_disabled"
            entities.select { |entity| entity[:value] == "disabled" }
          else
            []
          end
        end

        sig do
          params(
            all_policies: Copilot::Users::Policies::CopilotAllPolicies,
            policy: Symbol,
          ).returns(T::Array[Entity])
        end
        def policy_entities(all_policies, policy)
          all_policies.filter_map do |data|
            config = data[:config]
            next unless config

            value = config[policy]
            normalized_value = policy_value(value)
            next unless normalized_value

            entity = T.let({
              policy: policy.to_s,
              type: data[:type].to_s,
              id: data[:id],
              name: data[:name],
              value: normalized_value,
            }, Entity)
            entity[:parent_id] = data[:parent_id] if data.key?(:parent_id)
            entity
          end
        end

        sig { params(value: T.nilable(T.any(String, Symbol))).returns(T.nilable(String)) }
        def policy_value(value)
          normalized_value = value.to_s
          return "enabled" if normalized_value == "allowed"
          return "disabled" if normalized_value == "blocked"

          normalized_value if %w[enabled disabled unconfigured no_policy].include?(normalized_value)
        end

        sig do
          params(
            copilot_user: Copilot::User,
            all_policies: Copilot::Users::Policies::CopilotAllPolicies,
            effective_value: String,
          ).returns(String)
        end
        def cli_remote_control_policy_reason(copilot_user, all_policies, effective_value)
          return "enabled_by_policy" if effective_value == "enabled"
          return "feature_or_plan_unavailable" unless Copilot::Policies::CliRemoteControl.available_for?(copilot_user)
          return "cloud_session_storage_policy_disabled" if cli_cloud_session_storage_inherited_value(copilot_user, all_policies) == "disabled"
          return "enabled_by_default" if copilot_user.has_cfi_access?

          inherited_reason(all_policies, :cli_remote_control)
        end

        sig do
          params(
            copilot_user: Copilot::User,
            all_policies: Copilot::Users::Policies::CopilotAllPolicies,
            effective_value: String,
          ).returns(String)
        end
        def cli_cloud_session_storage_policy_reason(copilot_user, all_policies, effective_value)
          return "enabled_by_policy" if effective_value == "enabled"
          return "feature_or_plan_unavailable" unless Copilot::Policies::CliCloudSessionStorage.available_for?(copilot_user)
          return "enabled_by_default" if copilot_user.has_cfi_access?

          inherited_reason(all_policies, :cli_cloud_session_storage)
        end

        sig { params(all_policies: Copilot::Users::Policies::CopilotAllPolicies, policy: Symbol).returns(String) }
        def inherited_reason(all_policies, policy)
          entities = policy_entities(all_policies, policy)
          return "business_policy_disabled" if entities.any? { |entity| entity[:type] == "business" && entity[:value] == "disabled" }
          return "organization_policy_disabled" if entities.any? { |entity| entity[:type] == "organization" && entity[:value] == "disabled" }

          "no_enabled_policy"
        end

        sig { params(reason: String).returns(String) }
        def cli_remote_control_required_fix(reason)
          case reason
          when "cloud_session_storage_policy_disabled"
            "enable_cli_cloud_session_storage_and_cli_remote_control"
          when "feature_or_plan_unavailable"
            "enable_feature_or_plan"
          when "no_enabled_policy"
            "configure_an_org_or_business_policy"
          else
            "enable_cli_remote_control"
          end
        end

        sig { params(reason: String).returns(String) }
        def cli_cloud_session_storage_required_fix(reason)
          case reason
          when "feature_or_plan_unavailable"
            "enable_feature_or_plan"
          when "no_enabled_policy"
            "configure_an_org_or_business_policy"
          else
            "enable_cli_cloud_session_storage"
          end
        end

        sig { params(copilot_user: Copilot::User, all_policies: Copilot::Users::Policies::CopilotAllPolicies).returns(T.nilable(Symbol)) }
        def cli_remote_control_blocking_policy(copilot_user, all_policies)
          :cli_cloud_session_storage if cli_cloud_session_storage_inherited_value(copilot_user, all_policies) == "disabled"
        end

        sig { params(copilot_user: Copilot::User, all_policies: Copilot::Users::Policies::CopilotAllPolicies).returns(T.nilable(String)) }
        def cli_cloud_session_storage_inherited_value(copilot_user, all_policies)
          Copilot::Policies::CliCloudSessionStorage.user_inherited_policy(copilot_user, all_policies, skip_ea_fallback: true)
        end
      end
    end
  end
end
