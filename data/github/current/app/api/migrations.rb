# typed: true
# frozen_string_literal: true

class Api::Migrations < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    require_authentication!

    set_forbidden_message("Authorization failed. Please visit https://docs.github.com/migrations/using-ghe-migrator/exporting-migration-data-from-githubcom for more information.")
  end

  def ip_allowlist_enforceable
    return :no if hmac_authenticated_internal_service_request?
    :yes
  end

  post "/organizations/:organization_id/migrations", operation_id: "migrations/start-for-org" do
    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    data = receive_with_openapi

    lock = data.fetch("lock_repositories", false)
    exclude_metadata = data.fetch("exclude_metadata", false)
    exclude_git_data = data.fetch("exclude_git_data", false)
    exclude_attachments = data.fetch("exclude_attachments", false)
    exclude_releases = data.fetch("exclude_releases", false)
    exclude_owner_projects = data.fetch("exclude_owner_projects", false)
    exclude = data.fetch("exclude", [])
    org_metadata_only = data.fetch("org_metadata_only", false)
    use_octoshift = data.fetch("use_octoshift", false)

    repos, errors = validate_repositories_data_and_populate_repos(data["repositories"], owner, org_metadata_only)
    deliver_error! 422, errors: errors if errors.any?

    octoshift_migration_id = ActionDispatch::Http::Headers.from_hash(env)["HTTP_X_GITHUB_OCTOSHIFT_MIGRATION_ID"].to_s

    migration = GitHub.migrator.export_later \
      repos: repos,
      owner: owner,
      current_user: current_user,
      lock: lock,
      exclude_metadata: exclude_metadata,
      exclude_git_data: exclude_git_data,
      exclude_attachments: exclude_attachments,
      exclude_releases: exclude_releases,
      exclude_owner_projects: exclude_owner_projects,
      org_metadata_only: org_metadata_only,
      use_octoshift: use_octoshift,
      octoshift_migration_id: octoshift_migration_id

    deliver :migration_hash, migration, status: 201, exclude: exclude
  end

  post "/user/migrations", operation_id: "migrations/start-for-authenticated-user" do
    owner = find_owner!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    data = receive_with_schema("migration", "create-for-user")
    lock = data.fetch("lock_repositories", false)
    exclude_metadata = data.fetch("exclude_metadata", false)
    exclude_git_data = data.fetch("exclude_git_data", false)
    exclude_attachments = data.fetch("exclude_attachments", false)
    exclude_releases = data.fetch("exclude_releases", false)
    exclude_owner_projects = data.fetch("exclude_owner_projects", false)
    exclude = data.fetch("exclude", [])
    org_metadata_only = data.fetch("org_metadata_only", false)

    repos, errors = validate_repositories_data_and_populate_repos(data["repositories"], owner)
    deliver_error! 422, errors: errors if errors.any?

    octoshift_migration_id = ActionDispatch::Http::Headers.from_hash(env)["HTTP_X_GITHUB_OCTOSHIFT_MIGRATION_ID"].to_s

    migration = GitHub.migrator.export_later \
      repos: repos,
      owner: owner,
      current_user: current_user,
      lock: lock,
      exclude_metadata: exclude_metadata,
      exclude_git_data: exclude_git_data,
      exclude_attachments: exclude_attachments,
      exclude_releases: exclude_releases,
      exclude_owner_projects: exclude_owner_projects,
      org_metadata_only: org_metadata_only,
      octoshift_migration_id: octoshift_migration_id

    deliver :migration_hash, migration, status: 201, exclude: exclude
  end

  get "/organizations/:organization_id/migrations", operation_id: "migrations/list-for-org" do
    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    exclude = params.fetch(:exclude, [])

    migrations = paginate_rel(Migration.for_owner(owner).newest)
    prefill_migrations(migrations)

    deliver :migration_hash, migrations, status: 200, exclude: exclude
  end

  get "/user/migrations", operation_id: "migrations/list-for-authenticated-user" do

    owner = find_owner!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    exclude = params.fetch(:exclude, [])

    migrations = paginate_rel(Migration.for_owner(owner).newest)
    prefill_migrations(migrations)

    deliver :migration_hash, migrations, status: 200, exclude: exclude
  end

  get "/organizations/:organization_id/migrations/:migration_id", operation_id: "migrations/get-status-for-org" do
    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    exclude = params.fetch(:exclude, [])

    migration = find_migration!(owner)

    deliver :migration_hash, migration, status: 200, exclude: exclude
  end

  get "/user/migrations/:migration_id", operation_id: "migrations/get-status-for-authenticated-user" do
    owner = find_owner!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    exclude = params.fetch(:exclude, [])

    migration = find_migration!(owner)

    deliver :migration_hash, migration, status: 200, exclude: exclude
  end

  get "/organizations/:organization_id/migrations/:migration_id/repositories", operation_id: "migrations/list-repos-for-org" do

    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)

    Repository.prefill_associations(migration.repositories)

    serializer = changeset_active?(:restrict_repo_fields_in_migration_resource) ? :simple_repository_hash : :repository_hash
    deliver serializer, migration.repositories, status: 200
  end

  get "/user/migrations/:migration_id/repositories", operation_id: "migrations/list-repos-for-authenticated-user" do
    owner = find_owner!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)

    Repository.prefill_associations(migration.repositories)

    serializer = changeset_active?(:restrict_repo_fields_in_migration_resource) ? :simple_repository_hash : :repository_hash
    deliver serializer, migration.repositories, status: 200
  end

  get "/organizations/:organization_id/migrations/:migration_id/archive", operation_id: "migrations/download-archive-for-org" do

    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)
    file      = find_migration_file!(migration)

    file.download
    status 302
    response["location"] = file.download_url(actor: current_user)
  end

  get "/user/migrations/:migration_id/archive", operation_id: "migrations/get-archive-for-authenticated-user" do
    owner = find_owner!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)
    file      = find_migration_file!(migration)

    file.download
    status 302
    response["location"] = file.download_url(actor: current_user)
  end

  patch "/organizations/:organization_id/migrations/:migration_id/archive", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    org       = find_org!
    control_access :write_migration, resource: org, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(org)
    file      = find_migration_file!(migration)

    data = receive(Hash)

    if data["state"] == "uploaded"
      file.supports_multi_part_upload = !!data["is_multipart"]

      saved = file.track_uploaded
      if saved
        migration.upload_archive!
        return deliver :migration_hash, migration, status: 201
      else
        return deliver_error 422,
          errors: file.errors
      end
    end

    # We don't allow changing other attributes of migration files right now.
    deliver_error 422,
      errors: [],
      documentation_url: "Currently, only migration file state can be changed."
  end

  delete "/organizations/:organization_id/migrations/:migration_id/archive", operation_id: "migrations/delete-archive-for-org" do
    # Introducing strict validation of the migration.delete-org-archive
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("migration", "delete-org-archive", skip_validation: true)

    owner = find_org!
    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)
    find_migration_file!(migration)

    MigrationDestroyFileJob.enqueue(migration)
    deliver_empty(status: 204)
  end

  delete "/user/migrations/:migration_id/archive", operation_id: "migrations/delete-archive-for-authenticated-user" do
    receive_with_schema("migration", "delete-user-archive")

    owner = find_owner!

    control_access :migration_export, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    migration = find_migration!(owner)
    find_migration_file!(migration)

    MigrationDestroyFileJob.enqueue(migration)
    deliver_empty(status: 204)
  end

  delete "/organizations/:organization_id/migrations/:migration_id/repos/:repo/lock", operation_id: "migrations/unlock-repo-for-org" do
    # Introducing strict validation of the migration.unlock-repo
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("migration", "unlock-repo", skip_validation: true)

    org       = find_org!

    if is_gei_migration_id?(params[:migration_id])
      deliver_error! 400, message: "You cannot unlock a repository locked by a GitHub Enterprise Importer (GEI) migration using this API. Please contact GitHub Support."
    end

    migration = find_migration!(org)
    repo      = record_or_404(migration.repositories.find_by_name(params[:repo]))
    set_current_repo_for_access_control(repo)
    control_access :migration_export, resource: org, forbid: current_repo.public?, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    current_repo.unlock_excluding_descendants! if current_repo.locked_on_migration?

    deliver_empty(status: 204)
  end

  delete "/user/migrations/:migration_id/repos/:repo/lock", operation_id: "migrations/unlock-repo-for-authenticated-user" do
    receive_with_schema("migration", "unlock")

    owner     = find_owner!
    migration = find_migration!(owner)
    repo      = record_or_404(migration.repositories.find_by_name(params[:repo]))
    set_current_repo_for_access_control(repo)
    control_access :migration_repo_unlock, repo: repo, forbid: current_repo.public?, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    if current_repo.locked_on_migration?
      current_repo.unlock_excluding_descendants!
      deliver_empty(status: 204)
    else
      deliver_error! 404
    end
  end

  # Look up repositories and ensure they're OK to export.
  #
  # * The repository must exist.
  # * The repository must be adminable_by the current_user.
  # * The repository must be in the org from the request URL.
  # * The repository must be public if the current_user has OFAC restrictions
  # * The repositories should be empty if org metadata export.
  # * There must be repositories given, unless the org_data_only flag is passed in.
  def validate_repositories_data_and_populate_repos(repositories_data, owner, org_metadata_only = false)
    repos  = []
    errors = []


    if org_metadata_only && repositories_data.present?
      errors.push resource: "Migration", field: "repositories", code: "invalid_value"
      return [repos, errors]
    end

    repositories_data.each_with_index do |name, i|
      repo = owner.repositories.find_by_name(name) || Repository.with_name_with_owner(name)

      if repo && repo.owner.to_s == owner.to_s && !ofac_restricted?(repo, owner)
        repos << repo
      else
        errors.push resource: "Migration", field: "repositories", index: i, code: "invalid_value"
      end
    end

    if repos.empty? && !org_metadata_only
      errors.push resource: "Migration", field: "repositories", code: "missing_field"
    end

    if GitHub.enterprise? && !GitHub.migrations_blob_storage_type.present?
      errors.push(
        resource: "Migration",
        code: :unprocessable,
        message: "Before you can start a migration, you must configure blob storage settings in your management console."
      )
    end

    [repos, errors]
  end

  # Private Is the migration for the given repo and owner ofac restricted?
  #
  # repo - Repository being migrated
  # owner - Organization or User that the Migration belongs to.
  #
  # Returns Boolean
  def ofac_restricted?(repo, owner)
    repo.private? && owner.has_any_trade_restrictions?
  end

  # Find Migration for request.
  #
  # owner - Organization or User that Migration belongs to.
  #
  # Returns a Migration or halts request early with a 404.
  def find_migration!(owner)
    record_or_404 find_migration(owner)
  end

  # Find Migration for request.
  #
  # owner - Organization or User that Migration belongs to.
  #
  # Returns a Migration or nil
  def find_migration(owner)
    Migration.for_owner(owner).find_by(id: params[:migration_id])
  end

  # Find the MigrationFile for this Migration.
  #
  # migration - Migration that MigrationFile belongs to.
  #
  # Returns a MigrationFile or halts request early with a 404.
  def find_migration_file!(migration)
    record_or_404 migration.file
  end

  def find_owner!
    record_or_404 find_owner
  end

  def find_owner
    return current_integration_installation.target if current_integration_installation
    current_actor
  end

  def is_gei_migration_id?(migration_id)
    migration_id.starts_with?("RM_") || migration_id.starts_with?("OM_")
  end

  def prefill_migrations(migrations)
    GitHub::PrefillAssociations.prefill_associations(migrations, [:owner, :file])
    Repository.prefill_associations migrations.map(&:repositories).flatten
  end
end
