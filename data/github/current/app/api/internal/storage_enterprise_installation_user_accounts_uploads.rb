# typed: true
# frozen_string_literal: true

# Implements the API that alambic uses for serving or accepting Enterprise
# Server installation user accounts uploads through the alambic storage cluster.
# Used in local development.
class Api::Internal::StorageEnterpriseInstallationUserAccountsUploads < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/businesses/:slug/user-accounts-uploads/:guid", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = get_business(params[:slug])
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false

    upload = business.enterprise_installation_user_accounts_uploads.find_by guid: params[:guid]
    deliver :internal_storage_hash, upload, env: request.env
  end

  post "/internal/storage/businesses/:slug/user-accounts-uploads", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = get_business(params[:slug])
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false
    validate_uploadable EnterpriseInstallationUserAccountsUpload,
      meta: { business_id: business.id }
  end

  post "/internal/storage/businesses/:slug/user-accounts-uploads/verify", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = get_business(params[:slug])
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false
    create_uploadable EnterpriseInstallationUserAccountsUpload,
      meta: { business_id: business.id }
  end

  def verify_user(meta)
    T.unsafe(EnterpriseInstallationUserAccountsUpload).storage_verify_token(@asset_token, meta)
  end

  private

  def get_business(slug)
    business = ActiveRecord::Base.connected_to(role: :reading) do
      Business.where(slug: slug).first
    end
    business || deliver_error!(404, message: "cannot find business with slug \`#{slug}\`")
  end
end
