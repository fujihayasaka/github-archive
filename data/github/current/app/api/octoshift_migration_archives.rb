# typed: true
# frozen_string_literal: true

class Api::OctoshiftMigrationArchives < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    require_authentication!
  end

  def ip_allowlist_enforceable
    hmac_authenticated_internal_service_request? ? :no : :yes
  end

  patch "/organizations/:organization_id/gei/archive/:guid", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = find_org!

    deliver_error!(404) unless github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: "Must have GitHub Enterprise Importer (GEI) import rights to Organization.",
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )

    octoshift_migration_archive = find_octoshift_migration_archive!(
      guid: params[:guid],
      organization_id: params[:organization_id]
    )

    data = receive(Hash)

    if data["state"] == "uploaded"
      saved = octoshift_migration_archive.track_uploaded

      if saved
        deliver :octoshift_migration_archive_hash, octoshift_migration_archive, status: 201
      else
        deliver_error 422, errors: octoshift_migration_archive.errors
      end
    else
      deliver_error 422, message: "Only GEI archive states can be changed."
    end
  end

  private

  # Find a OctoshiftMigrationArchive record, or deliver a 404 if not found.
  #
  # @param [String] id Database ID for OctoshiftMigrationArchive record.
  # @param [String] organization_id Database ID for Organization record.
  # @return [OctoshiftMigrationArchive] OctoshiftMigrationArchive record.
  def find_octoshift_migration_archive!(guid:, organization_id:)
    record_or_404 OctoshiftMigrationArchive.find_by(guid: guid, organization_id: organization_id)
  end

  # Determine if GitHub-owned storage is enabled via the octoshift_github_owned_storage feature flag.
  #
  # @param [Organization] organization Organization to check for the octoshift_github_owned_storage feature flag.
  # @return [true, false] Feature flag state of octoshift_github_owned_storage for the organization.
  def github_owned_storage_enabled?(organization)
    GitHub.flipper[:octoshift_github_owned_storage].enabled?(organization)
  end
end
