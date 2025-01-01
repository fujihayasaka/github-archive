# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module EnterpriseAccounts
      def enterprise_accounts_storage_type
        @enterprise_accounts_storage_type ||= "s3"
      end
      attr_writer :enterprise_accounts_storage_type

      attr_accessor :enterprise_accounts_storage_azure_account_name
      attr_accessor :enterprise_accounts_storage_azure_spn_tenant_id
      attr_accessor :enterprise_accounts_storage_azure_spn_client_id
      attr_accessor :enterprise_accounts_storage_azure_spn_client_secret
    end
  end

  extend Config::EnterpriseAccounts
end
