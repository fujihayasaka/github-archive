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

  private

  def language_is_onboarded?(repo, language)
    repo.languages_onboarded_for_codeql_bulk_building.include?(language)
  end
end
