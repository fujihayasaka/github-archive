# typed: true
# frozen_string_literal: true

# Internal API endpoints for creating MultiPart S3 Policies.
# Used by github/github and not meant for public
# consumption.
class Api::Internal::MultiPartPolicies < Api::Internal

  before do
    require_api_semantic_version "jalebi"
  end

  def ip_allowlist_enforceable
    return :no if hmac_authenticated_internal_service_request?
    :yes
  end

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
end
