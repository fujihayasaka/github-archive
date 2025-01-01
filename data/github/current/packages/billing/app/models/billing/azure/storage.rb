# typed: strict
# frozen_string_literal: true

module Billing::Azure
  class Storage
    extend T::Sig
    class Config < T::Struct
      const :name, String
      const :tenant_id, T.nilable(String)
      const :client_id, T.nilable(String)
      const :client_secret, T.nilable(String)
      const :storage_account_name, T.nilable(String)
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
        client_secret: GitHub.account_management_azure_spn_client_secret,
        storage_account_name: GitHub.account_management_azure_storage_account_name
      )
    end
  end
end
