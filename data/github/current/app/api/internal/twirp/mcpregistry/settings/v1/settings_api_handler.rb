# typed: true
# frozen_string_literal: true

require "monolith-twirp-mcpregistry-settings"

module Api::Internal::Twirp::Mcpregistry
  module Settings
    module V1
      # Handler for the MonolithTwirp::Mcpregistry::Settings::V1::SettingsAPIService
      class SettingsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["mcp_registry"]
        handles_service MonolithTwirp::Mcpregistry::Settings::V1::SettingsAPIService
        MAX_BATCH_SIZE = 500

        # Public: Implementation of the GetEnterpriseSettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Settings::V1::GetEnterpriseSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Settings::V1::GetEnterpriseSettingsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Settings::V1::GetEnterpriseSettingsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Settings::V1::GetEnterpriseSettingsResponse, Twirp::Error))
        end
        def get_enterprise_settings(req, env)
          enterprise_id = req.enterprise_id
          return Twirp::Error.invalid_argument("enterprise_id must be > 0") if enterprise_id <= 0

          business = Business.find_by(id: enterprise_id)
          return Twirp::Error.not_found("not found") if business.nil?

          MonolithTwirp::Mcpregistry::Settings::V1::GetEnterpriseSettingsResponse.new(
            settings: MonolithTwirp::Mcpregistry::Settings::V1::EnterpriseSettings.new(
              enterprise_id: business.id,
              mcp_policy: enterprise_mcp_policy(business),
            ),
          )
        end
        # Public: Implementation of the BatchGetEnterpriseSettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Settings::V1::BatchGetEnterpriseSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Settings::V1::BatchGetEnterpriseSettingsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Settings::V1::BatchGetEnterpriseSettingsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Settings::V1::BatchGetEnterpriseSettingsResponse, Twirp::Error))
        end
        def batch_get_enterprise_settings(req, env)
          enterprise_ids = req.enterprise_ids.to_a
          if enterprise_ids.size > MAX_BATCH_SIZE
            return Twirp::Error.invalid_argument("enterprise_ids must not exceed #{MAX_BATCH_SIZE} items", argument: "enterprise_ids")
          end

          businesses_by_id = Business.where(id: enterprise_ids).index_by(&:id)
          mcp_settings_by_enterprise_id = batch_load_enterprise_mcp_settings(enterprise_ids)
          settings = enterprise_ids.filter_map do |enterprise_id|
            business = businesses_by_id[enterprise_id]
            next if business.nil?

            MonolithTwirp::Mcpregistry::Settings::V1::EnterpriseSettings.new(
              enterprise_id: business.id,
              mcp_policy: mcp_policy_from_setting(mcp_settings_by_enterprise_id[enterprise_id]),
            )
          end

          MonolithTwirp::Mcpregistry::Settings::V1::BatchGetEnterpriseSettingsResponse.new(settings: settings)
        end

        private

        sig { params(business: Business).returns(T.any(Symbol, Integer)) }
        def enterprise_mcp_policy(business)
          mcp_policy_from_setting(Copilot::Business.new(business).configuration.mcp)
        end

        sig { params(mcp_setting: T.nilable(String)).returns(T.any(Symbol, Integer)) }
        def mcp_policy_from_setting(mcp_setting)
          if mcp_setting == "disabled"
            MonolithTwirp::Mcpregistry::Settings::V1::EnterpriseSettings::MCPPolicy::MCP_POLICY_DISABLED
          elsif mcp_setting == "enabled"
            MonolithTwirp::Mcpregistry::Settings::V1::EnterpriseSettings::MCPPolicy::MCP_POLICY_ENABLED
          else
            MonolithTwirp::Mcpregistry::Settings::V1::EnterpriseSettings::MCPPolicy::MCP_POLICY_NO_POLICY
          end
        end

        sig { params(enterprise_ids: T::Array[Integer]).returns(T::Hash[Integer, String]) }
        def batch_load_enterprise_mcp_settings(enterprise_ids)
          configuration_scope = Copilot::Configuration.batched_scope(:configurable_id, values: enterprise_ids) do |scope|
            scope.where(configurable_type: "Business")
          end

          configuration_scope.pluck(:configurable_id, :mcp).to_h
        end
      end
    end
  end
end
