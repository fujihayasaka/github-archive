# typed: strict
# frozen_string_literal: true

module Billing::Azure
  class Storage
    class Config < T::Struct
      include GitHub::Azure::OIDCTokenProvider::AzureCredentialConfig

      const :name, String
      const :tenant_id, T.nilable(String)
      const :client_id, T.nilable(String)
      const :client_secret, T.nilable(String)
      const :storage_account_name, T.nilable(String)

      sig { override.returns(T.nilable(String)) }
      def azure_client_id
        client_id
      end

      sig { override.returns(T.nilable(String)) }
      def azure_tenant_id
        tenant_id
      end

      sig { override.returns(String) }
      def config_name
        name
      end

      sig { returns(T::Boolean) }
      def use_oidc?
        client_secret.blank?
      end
    end

    sig { returns(Config) }
    def self.metered_billing_config
      Config.new(
        name: "metered_billing",
        tenant_id: GitHub.metered_billing_azure_spn_tenant_id,
        client_id: GitHub.metered_billing_azure_spn_client_id,
        client_secret: GitHub.metered_billing_azure_spn_client_secret,
        storage_account_name: GitHub.metered_billing_azure_storage_account_name
      )
    end

    sig { returns(Config) }
    def self.account_management_config
      Config.new(
        name: "account_management",
        tenant_id: GitHub.account_management_azure_spn_tenant_id,
        client_id: GitHub.account_management_azure_spn_client_id,
        client_secret: nil,
        storage_account_name: GitHub.account_management_azure_storage_account_name
      )
    end
  end
end
