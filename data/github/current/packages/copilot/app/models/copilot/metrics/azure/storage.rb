# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  module Azure
    class Storage
      class Config < T::Struct
        const :name, String
        const :tenant_id, T.nilable(String)
        const :client_id, T.nilable(String)
        const :client_secret, T.nilable(String)
        const :storage_account_name, T.nilable(String)
      end

      sig { returns(Config) }
      def self.copilot_user_engagement_config
        Config.new(
          name: "copilot_user_engagement",
          tenant_id: GitHub.copilot_user_engagement_spn_tenant_id,
          client_id: GitHub.copilot_user_engagement_spn_client_id,
          client_secret: GitHub.copilot_user_engagement_spn_client_secret,
          storage_account_name: GitHub.copilot_user_engagement_storage_account_name
        )
      end

      sig { returns(Config) }
      def self.copilot_direct_data_access_config
        Config.new(
          name: "copilot_direct_data_access",
          tenant_id: GitHub.copilot_user_engagement_spn_tenant_id,
          client_id: GitHub.copilot_user_engagement_spn_client_id,
          client_secret: GitHub.copilot_user_engagement_spn_client_secret,
          storage_account_name: GitHub.copilot_direct_data_access_storage_account_name
        )
      end
    end
  end
end
