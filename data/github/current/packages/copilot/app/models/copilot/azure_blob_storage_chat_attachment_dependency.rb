# typed: strict
# frozen_string_literal: true

module Copilot
  module AzureBlobStorageChatAttachmentDependency
    extend T::Helpers
    include Storage::AzureBlobStorageDependency

    abstract!

    # Client ID for the Service Principal used to connect to Azure resources
    # Defaults to using the memory alpha credentials, as these are commonly used to
    # access ABS resources
    sig { override.returns(String) }
    def abs_spn_client_id
      GitHub.spn_memory_alpha_client_id
    end

    # Client Secret for the Service Principal used to connect to Azure resources
    # Defaults to using the memory alpha credentials, as these are commonly used to
    # access ABS resources
    sig { override.returns(String) }
    def abs_spn_client_secret
      GitHub.spn_memory_alpha_client_secret
    end

    # Tenant ID for the Service Principal used to connect to Azure resources
    # Defaults to using the memory alpha credentials, as these are commonly used to
    # access ABS resources
    sig { override.returns(String) }
    def abs_spn_tenant_id
      GitHub.spn_memory_alpha_tenant_id
    end

    sig { returns(String) }
    def self.abs_storage_account_name
      GitHub.copilot_chat_attachment_azure_storage_account
    end

    # Storage account name for Azure Blob Storage Account
    # This is used in the generation of ABS URLS, i.e. http://<account_name>.blob.core.windows.net
    sig { override.returns(String) }
    def abs_storage_account_name
      AzureBlobStorageChatAttachmentDependency.abs_storage_account_name
    end

    sig { returns(String) }
    def self.storage_abs_container
      GitHub.copilot_chat_attachment_azure_storage_container
    end

    # Container name to be accessed within the Azure Blob Storage Account
    # This can be thought of as a correlary to an AWS bucket.
    sig { override.returns(String) }
    def storage_abs_container
      AzureBlobStorageChatAttachmentDependency.storage_abs_container
    end
  end
end
