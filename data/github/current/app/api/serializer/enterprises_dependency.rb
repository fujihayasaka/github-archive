# typed: true
# frozen_string_literal: true

module Api::Serializer::EnterprisesDependency
  extend T::Helpers
  include Api::Serializer::AvatarsDependency
  include Api::Serializer::UserDependency
  include Api::Serializer::CustomPropertiesDependency

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  #
  # business  - Business instance
  # options   - Hash
  #
  # Returns a Hash if the business exists, or nil.
  def business_hash(business, options = {})
    return nil unless business
    {
      id: business.id,
      slug: business.slug,
      name: business.name,
      node_id: global_id_for(business, options),
      avatar_url: avatar(business),
      description: business.description,
      website_url: business.website_url,
      html_url: html_url("/enterprises/#{business}"),
      created_at: time(business.created_at),
      updated_at: time(business.updated_at),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # upload - EnterpriseInstallationUserAccountsUpload
  # options - Hash
  #
  # Returns a Hash if the upload exists, otherwise nil.
  def enterprise_installation_user_accounts_upload_hash(upload, options = {})
    return nil unless upload

    business = upload.business
    upload_path = "/businesses/#{business.slug}/user-accounts-uploads/#{upload.id}"

    {
      id: upload.id,
      name: upload.name,
      uploader: simple_user_hash(upload.uploader, content_options(options)),
      content_type: upload.content_type,
      state: upload.state,
      size: upload.size,
      created_at: time(upload.created_at),
      updated_at: time(upload.updated_at),
      sync_state: upload.sync_state,
      url: url(upload_path, options),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data - Hash containing :announcement and :expires_at keys
  # options - Hash
  #
  # Returns Hash.
  def enterprise_announcement_hash(data, options = {})
    {
      announcement: data[:announcement],
      expires_at: data[:expires_at],
      user_dismissible: !!data[:user_dismissible],
    }
  end
end
