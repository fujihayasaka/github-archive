# typed: strict
# frozen_string_literal: true
class Licensing::GhesKeypair
  extend T::Helpers

  GHES_KEYPAIRS_CONTAINER = "licensing-ghes-keypairs"
  @azure_blob_client = T.let(nil, T.nilable(Licensing::AzureBlobClient))

  sig { returns(String) }
  attr_accessor :business_id

  sig { returns(T.nilable(String)) }
  attr_accessor :secret_key_data

  sig { returns(T.nilable(String)) }
  attr_accessor :public_key_data

  sig { returns(T.nilable(String)) }
  attr_accessor :support_secret_key

  sig { returns(T.nilable(String)) }
  attr_accessor :support_public_key

  sig do
    params(
      business_id: String,
      secret_key_data: T.nilable(String),
      public_key_data: T.nilable(String),
      support_secret_key: T.nilable(String),
      support_public_key: T.nilable(String)
    ).void
  end
  def initialize(business_id:, secret_key_data:, public_key_data:, support_secret_key: nil, support_public_key: nil)
    @business_id = business_id
    @secret_key_data = secret_key_data
    @public_key_data = public_key_data
    @support_secret_key = support_secret_key
    @support_public_key = support_public_key
  end

  sig { returns(T.nilable(::Azure::Storage::Blob::Blob)) }
  def save!
    data = {
      business_id: @business_id,
      secret_key_data: @secret_key_data,
      public_key_data: @public_key_data,
      support_secret_key: @support_secret_key,
      support_public_key: @support_public_key
    }
    self.class.azure_blob_client.upload(
      GHES_KEYPAIRS_CONTAINER,
      self.class.blob_name_from_id(@business_id),
      data.to_json
    )
  end

  sig { params(business_id: String).returns(T.nilable(Licensing::GhesKeypair)) }
  def self.get_by_business_id(business_id)
    blob_name = blob_name_from_id(business_id)
    blob, content = azure_blob_client.get_blob(GHES_KEYPAIRS_CONTAINER, blob_name)
    if content.present?
      data = JSON.parse(content)
      new(**data.symbolize_keys)
    end
  end

  sig { returns(Licensing::AzureBlobClient) }
  def self.azure_blob_client
    @azure_blob_client ||= Licensing::AzureBlobClient.new
  end

  sig { params(id: String).returns(String) }
  def self.blob_name_from_id(id)
    "business:#{id}"
  end
end
