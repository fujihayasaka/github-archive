# typed: false
# frozen_string_literal: true

# Internal API endpoints for creating S3 Policies.
# Used exclusively by github/alambic_server, and not meant for public
# consumption.
class Api::Policies < Api::App
  include Api::App::CodeScanningHelpers
  include VariantAnalysis::RepositoryResolutionHelper

  ROUTES_EXCLUDED_FROM_CAP_CHECKS = [
    ["post", "/repositories/:repository_id/releases/:release_id/assets/policies"],
    ["post", "/repositories/:repository_id/code-scanning/codeql/databases/:language/policies"],
  ]

  def attempt_login
    endpoint = "#{request.request_method.downcase} #{route_pattern}"
    if endpoint == "post /repositories/:repository_id/code-scanning/codeql/databases/:language/policies"
      repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo }
      login_from_remote_token(Api::RepositoryCodeScanningDatabases.signed_auth_token_upload_scope(repo.id)) if repo
    end

    super unless @remote_token_auth
  end

  def ip_allowlist_enforceable
    return :no if ROUTES_EXCLUDED_FROM_CAP_CHECKS.include?(
      [request.request_method.downcase, route_pattern]
    ) && hmac_authenticated_internal_service_request?
    :yes
  end

  post "/repositories/:repository_id/releases/:release_id/assets/policies", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    deliver_error!(404) unless logged_in?

    release = Releases::Public.load_release(params[:release_id].to_i)
    record_or_404(release)

    rel = release.repository_id == params[:repository_id].to_i ? release : nil
    record_or_404(rel)

    repo = rel.repository
    record_or_404(repo)

    control_access :edit_release, repo: repo, resource: rel, allow_integrations: true, allow_user_via_granular_actor: true

    if release.immutable
      deliver_error! 422, message: "Cannot upload assets to an immutable release."
    end

    if GitHub.storage_cluster_enabled?
      meta = {}
      attributes = params.merge(receive(Hash))
      Releases::Public.storage_interface.uploadable_policy_attributes.each do |key|
        meta[key] = attributes[key.to_s]
      end

      blob = ::Storage::Blob.new(size: meta[:size])
      uploadable = Releases::Public.storage_interface.storage_new(current_user, blob, meta)
      unless uploadable.valid?
        log_uploadable_error(uploadable)
        deliver_error! 422, errors: uploadable.errors
      end
      policy = uploadable.storage_policy(actor: current_user)

      deliver! :policy_hash, policy, status: 201
    end

    creator = ::Storage.policy_creator.for(:releases)
    deliver_error!(404) unless creator

    data = attr(receive(Hash), *creator.attributes)
    params.each do |key, value|
      data[key.to_s] = value
    end

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      log_uploadable_error(uploadable)
      deliver_error 422, errors: uploadable.errors
    end
  end

  post "/user-attachments/assets/policies", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"

    unless hmac_authenticated_internal_service_request?
      log("HMAC authentication required for user-attachments/assets/policies endpoint")
      deliver_error!(404)
    end

    unless logged_in?
      log("User must be logged in to access user-attachments/assets/policies endpoint")
      deliver_error!(404)
    end

    creator = ::Storage.policy_creator.for(:assets)
    unless creator
      log("No policy creator found for user-attachments/assets/policies endpoint")
      deliver_error!(404)
    end

    data = attr(receive(Hash), *creator.attributes)
    params.each do |key, value|
      data[key.to_s] = value
    end

    unless data[:repository_id].present?
      log("repository_id is required for user-attachments/assets/policies endpoint", data)
      deliver_error!(404)
    end

    # Ensure the repository exists and the user has access to it.

    repo  = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by_id(data[:repository_id].to_i) }
    unless repo
      log("repository_id is invalid for user-attachments/assets/policies endpoint", data)
      deliver_error!(404)
    end

    log("Checking if user has access to repository", data)

    control_access :upload_user_attachments,
      repo: repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    log("User has access to the repository", data)

    if GitHub.storage_cluster_enabled?
      meta = {}
      UserAsset.uploadable_policy_attributes.each do |key|
        meta[key] = data[key.to_s]
      end

      blob = ::Storage::Blob.new(size: meta[:size])
      uploadable = UserAsset.storage_new(current_user, blob, meta)
      unless uploadable.valid?
        log_uploadable_error(uploadable)
        deliver_error! 422, errors: uploadable.errors
      end
      policy = uploadable.storage_policy(actor: current_user)
      deliver! :policy_hash, policy, status: 201
    end

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      log_uploadable_error(uploadable)
      deliver_error 422, errors: uploadable.errors
    end
  end


  def log_uploadable_error(uploadable)
    errs = {}
    uploadable.errors.each do |error|
      errs["#{error.attribute}_error"] = error.message
    end
    err = StandardError.new("Failed to create #{uploadable.class.name}")
    GitHub::Logger.log({
      err: err,
      request_id: GitHub.context[:request_id],
      uploadable_class: uploadable.class.name,
      uploadable_errors: errs,
    })
    Failbot.report_user_error(err)
  end

  post "/migrations/:migration_id/archive/policies", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/data-infrastructure"
    deliver_error!(404) unless logged_in?

    migration = ActiveRecord::Base.connected_to(role: :reading) { Migration.find_by_id(params[:migration_id].to_i) }
    owner = migration.try(:owner)

    control_access :write_migration, resource: owner, forbid: true, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    if GitHub.storage_cluster_enabled?
      meta = {}
      attributes = params.merge(receive(Hash))
      MigrationFile.uploadable_policy_attributes.each do |key|
        meta[key] = attributes[key.to_s]
      end

      blob = ::Storage::Blob.new(size: meta[:size])
      uploadable = MigrationFile.storage_new(current_user, blob, meta)
      unless uploadable.valid?
        deliver_error! 422, errors: uploadable.errors
      end
      policy = uploadable.storage_policy(actor: current_user)
      deliver! :policy_hash, policy, status: 201
    end

    creator = ::Storage.policy_creator.for(:migration_files)
    deliver_error!(404) unless creator

    deliver_error!(404) unless creator.access_allowed?(current_user, :write_migration, migration: migration, resource: owner)

    data = attr(receive(Hash), *creator.attributes)
    params.each do |key, value|
      data[key.to_s] = value
    end

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      deliver_error 422, errors: uploadable.errors
    end
  end

  post "/organizations/:organization_id/gei/archive/policies", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"

    deliver_error!(404) unless logged_in?

    organization = ActiveRecord::Base.connected_to(role: :reading) { Organization.find_by(id: params[:organization_id]) }

    deliver_error!(404) unless organization && github_owned_storage_enabled?(organization)

    control_access(
      :octoshift_import,
      resource: organization,
      forbid: true,
      forbid_message: "Must have GitHub Enterprise Importer (GEI) import rights to Organization.",
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )

    if GitHub.gei_archives_blob_storage_type == "s3"
      policy_creator = ::Storage.policy_creator.for(:octoshift_migration_archives)

      deliver_error!(404) unless policy_creator && policy_creator.access_allowed?(current_user, :octoshift_import, resource: organization)

      data = attr(receive(Hash), *policy_creator.attributes)
      params.each do |key, value|
        data[key.to_s] = value
      end

      octoshift_migration_archive = policy_creator.create(current_user, data)

      if octoshift_migration_archive.valid?
        policy = octoshift_migration_archive.storage_policy(actor: current_user)

        deliver :policy_hash, policy, status: 201
      else
        deliver_error 422, errors: octoshift_migration_archive.errors
      end
    else # Use local cluster storage.
      meta = {}
      attributes = params.merge(receive(Hash))
      OctoshiftMigrationArchive.uploadable_policy_attributes.each do |key|
        meta[key] = attributes[key.to_s]
      end

      blob = ::Storage::Blob.new(size: meta[:size])
      uploadable = OctoshiftMigrationArchive.storage_new(current_user, blob, meta)

      deliver_error! 422, errors: uploadable.errors unless uploadable.valid?

      policy = uploadable.storage_policy(actor: current_user)
      deliver! :policy_hash, policy, status: 201
    end
  end

  # rubocop:todo GitHub/ControlAccess
  post "/businesses/:slug/user-accounts-uploads/policies", operation_id: :internal do
    @route_owner = "@github/meao"
    deliver_error!(404) unless logged_in?

    business = ActiveRecord::Base.connected_to(role: :reading) do
      Business.where(slug: params[:slug]).first
    end

    if GitHub.storage_cluster_enabled?
      meta = {}
      attributes = params.merge(receive(Hash))
      EnterpriseInstallationUserAccountsUpload.uploadable_policy_attributes.each do |key|
        meta[key] = attributes[key.to_s]
      end
      meta[:business_id] = business.id

      blob = ::Storage::Blob.new(size: meta[:size])
      uploadable = EnterpriseInstallationUserAccountsUpload.storage_new(current_user, blob, meta)
      unless uploadable.valid?
        deliver_error! 422, errors: uploadable.errors
      end
      policy = uploadable.storage_policy(actor: current_user)
      deliver! :policy_hash, policy, status: 201
    end

    creator = ::Storage.policy_creator.for(:enterprise_installation_user_accounts_uploads)
    deliver_error!(404) unless creator

    deliver_error!(404) unless creator.access_allowed?(
      current_user, :write_business_enterprise_installation_user_accounts, resource: business
    )

    data = attr(receive(Hash), *creator.attributes)
    params.each do |key, value|
      data[key.to_s] = value
    end
    data[:business_id] = business.id

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      deliver_error 422, errors: uploadable.errors
    end
  end
  # rubocop:enable GitHub/ControlAccess

  post "/repositories/:repository_id/code-scanning/codeql/databases/:language/policies", operation_id: :internal do
    @route_owner = "@github/code-scanning-secexp"

    deliver_error! 404 if GitHub.enterprise?

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    if logged_into_public_repo_as_code_scanning_bot(repo)
      check_authorization do
        # As a special-case the code_scanning_bot is permitted to upload to any
        # public repository that we're autobuilding.
        deliver_error! 404 unless language_is_onboarded?(repo, params[:language])
        true
      end
    else
      ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
      control_access :write_codeql_database,
        resource: repo,
        forbid: repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    creator = ::Storage.policy_creator.for(:codeql_databases)
    deliver_error!(404) unless creator

    data = attr(receive(Hash), *creator.attributes)
    params.each do |key, value|
      data[key.to_s] = value
    end

    if data["commit_oid"] && !/\A[0-9a-f]{40}\z/i.match?(data["commit_oid"])
      deliver_error! 422, errors: "commit_oid must be a 40 character hex string"
    end

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      GitHub.dogstats.increment("code_scanning.codeql_database.policy_created")
      deliver :policy_hash, policy, status: 201
    else
      deliver_error 422, errors: uploadable.errors
    end
  end

  post "/copilot/chat/attachments/policies", operation_id: :internal do
    @route_owner = "@github/copilot-dotcom-chat"

    deliver_error!(404) if GitHub.enterprise?
    deliver_error!(404) unless logged_in?

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless current_user.feature_enabled?(:copilot_chat_attachments)

    copilot_user = Copilot::Public::User.new(current_user)

    deliver_error!(404) unless copilot_user.has_copilot_access?

    creator = ::Storage.policy_creator.for(:"copilot-chat-attachments")
    deliver_error!(404) unless creator

    data = attr(receive(Hash), *creator.attributes)
    params.each { |key, value| data[key.to_s] = value }

    uploadable = creator.create(current_user, data)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver :policy_hash, policy, status: 201
    else
      log_uploadable_error(uploadable)
      deliver_error 422, errors: uploadable.errors
    end
  end

  private

  def language_is_onboarded?(repo, language)
    repo.languages_onboarded_for_codeql_bulk_building.include?(language)
  end

  def github_owned_storage_enabled?(organization)
    GitHub.flipper[:octoshift_github_owned_storage].enabled?(organization)
  end

  def log(reason, data = {})
    GitHub.logger.info(reason, {
      request_id: GitHub.context[:request_id],
    }.merge(data))
  end
end
