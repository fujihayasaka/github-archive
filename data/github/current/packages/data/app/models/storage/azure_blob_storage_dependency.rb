# typed: strict
# frozen_string_literal: true

module Storage::AzureBlobStorageDependency
  extend T::Helpers

  abstract!

  # Client ID for the Service Principal used to connect to Azure resources
  sig { abstract.returns(String) }
  def abs_spn_client_id; end

  # Client Secret for the Service Principal used to connect to Azure resources
  sig { abstract.returns(String) }
  def abs_spn_client_secret; end

  # Tenant ID for the Service Principal used to connect to Azure resources
  sig { abstract.returns(String) }
  def abs_spn_tenant_id; end

  # Storage account name for Azure Blob Storage Account
  # This is used in the generation of ABS URLS, i.e. http://<account_name>.blob.core.windows.net
  sig { abstract.returns(String) }
  def abs_storage_account_name; end

  # Container name to be accessed within the Azure Blob Storage Account
  # This can be thought of as a correlary to an AWS bucket.
  sig { abstract.returns(String) }
  def storage_abs_container; end

  # Name of the item within the ABS container
  sig { abstract.params(policy: T.untyped).returns(String) }
  def storage_abs_key(policy);  end

  # Name of the key being used to retrieve the JWT key
  # in the Fastly dictionary
  sig { abstract.returns(T.nilable(String)) }
  def fastly_dictionary_key_name; end
end
