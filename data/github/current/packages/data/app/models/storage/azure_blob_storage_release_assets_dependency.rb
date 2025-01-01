# typed: strict
# frozen_string_literal: true

module Storage
  module AzureBlobStorageReleaseAssetsDependency
    extend T::Helpers
    include AzureBlobStorageDependency

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

    # Storage account name for Azure Blob Storage Account
    # This is used in the generation of ABS URLS, i.e. http://<account_name>.blob.core.windows.net
    sig { override.returns(String) }
    def abs_storage_account_name
      GitHub.release_assets_storage_acount
    end

    # Container name to be accessed within the Azure Blob Storage Account
    # This can be thought of as a correlary to an AWS bucket.
    sig { override.returns(String) }
    def storage_abs_container
      "github-#{Rails.env.downcase}-release-asset"
    end
  end
end
