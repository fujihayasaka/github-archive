# typed: true
# frozen_string_literal: true

# Internal API endpoints for creating MultiPart S3 Policies.
# Used by github/github and not meant for public
# consumption.
class Api::Internal::MultiPartPolicies < Api::Internal
  OCTOSHIFT_FORBID_MESSAGE = "Must have GitHub Enterprise Importer (GEI) import rights to Organization."

  before do
    require_api_semantic_version "jalebi"
  end

  def ip_allowlist_enforceable
    return :no if hmac_authenticated_internal_service_request?
    :yes
  end

  # Multipart policy routes for gh-migrator on .com.

  post "/internal/migrations/:migration_id/archive/multi-part/start/policies", operation_id: :internal do
    @route_owner = "@github/ee-osn"
    assert_dotcom_importer_access

    migration = migration_or_404(params[:migration_id].to_i)
    control_access :write_migration, resource: migration.owner, allow_user_via_granular_actor: false, allow_integrations: false

    # Only create migration_file once. If it exists, return it.
    if migration.file.nil?
      data = receive_with_schema("migration-multi-part-upload", "create")
      data["supports_multi_part_upload"] = true
      data["migration_id"] = migration.id

      create_policy :migration_files, data
    else
      migration_file = migration.file
      migration_file.set_multi_part_attributes!
      deliver_policy migration_file
    end
  end

  post "/internal/migrations/:migration_id/archive/multi-part/continue/policies", operation_id: :internal do
    @route_owner = "@github/ee-osn"
    assert_dotcom_importer_access

    migration = migration_or_404(params[:migration_id].to_i)
    control_access :write_migration, resource: migration.owner, allow_user_via_granular_actor: false, allow_integrations: false

    data = receive_with_schema("migration-multi-part-upload", "continue")

    migration_file = migration_file_or_404(data["guid"])

    migration_file.set_multi_part_attributes!(
      state: :multipart_upload_started,
      attributes: data,
    )

    deliver_policy migration_file
  end

  get "/internal/migrations/:migration_id/archive/multi-part/:guid/:multi_part_upload_id/list/policies", operation_id: :internal do
    @route_owner = "@github/ee-osn"
    assert_dotcom_importer_access

    migration = migration_or_404(params[:migration_id].to_i)
    control_access :write_migration, resource: migration.owner, allow_user_via_granular_actor: false, allow_integrations: false

    migration_file = migration_file_or_404(params[:guid])

    migration_file.set_multi_part_attributes(
      state: :multipart_upload_list_parts,
      attributes: params,
    )

    deliver_policy migration_file
  end

  post "/internal/migrations/:migration_id/archive/multi-part/complete/policies", operation_id: :internal do
    @route_owner = "@github/ee-osn"
    assert_dotcom_importer_access

    migration = migration_or_404(params[:migration_id].to_i)
    control_access :write_migration, resource: migration.owner, allow_user_via_granular_actor: false, allow_integrations: false

    data = receive_with_schema("migration-multi-part-upload", "complete")

    migration_file = migration_file_or_404(data["guid"])

    migration_file.set_multi_part_attributes!(
      state: :multipart_upload_completed,
      attributes: data,
    )

    deliver_policy migration_file
  end

  # Multipart policy routes for GitHub-owned storage for Octoshift.

  post "/internal/organizations/:organization_id/gei/archive/multi-part/start/policies", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(id: params[:organization_id])

    deliver_error!(404) unless github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: OCTOSHIFT_FORBID_MESSAGE,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false
    )

    data = receive_with_schema("gei-archive-multipart-upload", "create")
    data.merge!("supports_multi_part_upload" => true, "organization_id" => organization.id)

    create_policy :octoshift_migration_archives, data
  end

  post "/internal/organizations/:organization_id/gei/archive/multi-part/continue/policies", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(id: params[:organization_id])

    deliver_error!(404) unless github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: OCTOSHIFT_FORBID_MESSAGE,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false
    )

    data = receive_with_schema("gei-archive-multipart-upload", "continue")

    octoshift_migration_archive = find_octoshift_migration_archive!(guid: data["guid"], organization_id: params[:organization_id])
    octoshift_migration_archive.set_multi_part_attributes!(state: :multipart_upload_started, attributes: data)

    deliver_policy octoshift_migration_archive
  end

  get "/internal/organizations/:organization_id/gei/archive/multi-part/:guid/:multi_part_upload_id/list/policies", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(id: params[:organization_id])

    deliver_error!(404) unless github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: OCTOSHIFT_FORBID_MESSAGE,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false
    )

    octoshift_migration_archive = find_octoshift_migration_archive!(guid: params[:guid], organization_id: params[:organization_id])
    octoshift_migration_archive.set_multi_part_attributes(state: :multipart_upload_list_parts, attributes: params)

    deliver_policy octoshift_migration_archive
  end

  post "/internal/organizations/:organization_id/gei/archive/multi-part/complete/policies", operation_id: :internal do
    @route_owner = "@github/migration-tools"

    organization = get_organization!(id: params[:organization_id])

    deliver_error!(404) unless github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: OCTOSHIFT_FORBID_MESSAGE,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false
    )

    data = receive_with_schema("gei-archive-multipart-upload", "complete")

    octoshift_migration_archive = find_octoshift_migration_archive!(guid: data["guid"], organization_id: params[:organization_id])
    octoshift_migration_archive.set_multi_part_attributes!(state: :multipart_upload_completed, attributes: data)

    deliver_policy octoshift_migration_archive
  end

  private

  def create_policy(model, attributes = {})
    deliver_error!(404) unless
      creator = ::Storage.policy_creator.for(model)

    if block_given?
      deliver_error!(404) unless yield creator
    end

    deliver_policy creator.create(current_user, attributes.stringify_keys)
  end

  def deliver_policy(uploadable)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      deliver_error 422, errors: uploadable.errors
    end
  end

  def migration_or_404(migration_id)
    migration = ::Migration.find_by(id: migration_id)
    migration || deliver_error!(404, message: "cannot find migration with id \`#{migration_id}\`")
  end

  def migration_file_or_404(guid)
    migration_file = ::MigrationFile.find_by(guid: guid)
    migration_file || deliver_error!(404, message: "cannot find migration_file with guid \`#{guid}\`")
  end

  def assert_dotcom_importer_access
    @accepted_scopes = %w(admin:org)
    require_authentication!
    deliver_error!(404) unless GitHub.flipper[:gh_migrator_import_to_dotcom].enabled?(current_user)
  end

  # Determine if GitHub-owned storage is enabled via the octoshift_github_owned_storage feature flag.
  #
  # @param [Organization] organization Organization to check for the octoshift_github_owned_storage feature flag.
  # @return [Boolean] Feature flag state of octoshift_github_owned_storage for the organization.
  def github_owned_storage_enabled?(organization)
    GitHub.flipper[:octoshift_github_owned_storage].enabled?(organization)
  end

  # Find a OctoshiftMigrationArchive record, or deliver a 404 if not found.
  #
  # @param [String] guid GUID for OctoshiftMigrationArchive record.
  # @param [String] organization_id Database ID for Organization record.
  # @return [OctoshiftMigrationArchive] OctoshiftMigrationArchive record.
  def find_octoshift_migration_archive!(guid:, organization_id:)
    record_or_404 OctoshiftMigrationArchive.find_by(guid: guid, organization_id: organization_id)
  end

  # Find an Organization record, or deliver a 404 if not found.
  #
  # @param [String] id Database ID for Organization record.
  # @return [Organization] Organization record.
  def get_organization!(id:)
    record_or_404 Organization.find_by(id: id)
  end
end
