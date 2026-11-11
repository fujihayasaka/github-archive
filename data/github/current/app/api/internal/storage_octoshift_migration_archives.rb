# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting migration archive
# uploads through the Alambic storage cluster. Used in local development.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageOctoshiftMigrationArchives < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/organizations/:organization_id/gei/archive/:guid", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(organization_id: params[:organization_id])
    control_access :octoshift_admin, resource: organization, allow_integrations: false, allow_user_via_granular_actor: false

    archive = get_archive!(guid: params["guid"], organization_id: params["organization_id"])
    deliver :internal_storage_hash, archive, env: request.env
  end

  post "/internal/storage/organizations/:organization_id/gei/archive", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(organization_id: params[:organization_id])
    control_access :octoshift_admin, resource: organization, allow_integrations: false, allow_user_via_granular_actor: false

    validate_uploadable OctoshiftMigrationArchive, meta: { organization_id: organization.id }
  end

  post "/internal/storage/organizations/:organization_id/gei/archive/verify", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(organization_id: params[:organization_id])
    control_access :octoshift_admin, resource: organization, allow_integrations: false, allow_user_via_granular_actor: false

    create_uploadable OctoshiftMigrationArchive, meta: { organization_id: organization.id }
  end

  def verify_user(meta)
    OctoshiftMigrationArchive.storage_verify_token(@asset_token, meta)
  end

  private

  def get_organization!(organization_id:)
    ActiveRecord::Base.connected_to(role: :reading) { Organization.find_by(id: organization_id) }.tap do |organization|
      deliver_error!(404, message: "cannot find organization with ID \`#{organization_id}\`") unless organization
    end
  end

  def get_archive!(guid:, organization_id:)
    ActiveRecord::Base.connected_to(role: :reading) { OctoshiftMigrationArchive.find_by(guid: guid, organization_id: organization_id) }.tap do |archive|
      deliver_error!(404, message: "cannot find archive with GUID \`#{guid}\`") unless archive
    end
  end
end
