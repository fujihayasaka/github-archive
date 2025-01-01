# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningDatabases < Api::App
  include Api::App::CodeScanningHelpers

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  def ip_allowlist_enforceable
    return :no if request.request_method.downcase == "patch" &&
      route_pattern == "/repositories/:repository_id/code-scanning/codeql/databases/:language/:upload_id" &&
      hmac_authenticated_internal_service_request?
    :yes
  end

  def attempt_login
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo }

    if repo
      endpoint = "#{request.request_method.downcase} #{route_pattern}"
      if endpoint == "patch /repositories/:repository_id/code-scanning/codeql/databases/:language/:upload_id"
        scope = Api::RepositoryCodeScanningDatabases.signed_auth_token_upload_scope(repo.id)
      end

      login_from_remote_token(scope) if scope
    end

    super unless @remote_token_auth
  end

  # Called from alambic to update the state field of an upload after a user
  # uploads directly using the alambic endpoint:
  #
  # POST https://uploads.github.com/repositories/:repository_id/code-scanning/codeql/databases/:language
  patch "/repositories/:repository_id/code-scanning/codeql/databases/:language/:upload_id", operation_id: "code-scanning/update-codeql-database" do
    @route_owner = "@github/code-scanning-secexp"
    @accepted_scopes = %w(security_events repo)

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    if logged_into_public_repo_as_code_scanning_bot(repo)
      check_authorization do
        # As a special-case the code_scanning_bot is permitted to upload to any
        # public repository that we're autobuilding.
        deliver_error! 404 unless repo.languages_onboarded_for_codeql_bulk_building.include?(params[:language])
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

    # We are looking up this row by id and this endpoint may be called only seconds
    # after the row has been created in the policies endpoint.
    # Therefore deliberately connect to the primary instead of a replica.
    database = CodeqlDatabase.find_by \
      id: params[:upload_id], repository_id: repo.id, language: params[:language]
    deliver_error! 404 if database.nil?
    database = T.must(database)

    data = receive_with_openapi
    if data["state"] != "uploaded"
      # Don't allow any other attributes of uploads to be changed. This is a safety measure,
      # it should already have been validated by the OpenAPI schema.
      deliver_error! 422, message: "Only CodeQL database upload state can be changed."
    end

    # Place an upper bound on how long the upload of a database can take. This lets us
    # be more confident deleting databases that get stuck in the :starter state.
    if T.must(database.created_at) < CodeqlDatabase::UPLOAD_TIMEOUT.ago
      timeout_duration = ActiveSupport::Duration.build(CodeqlDatabase::UPLOAD_TIMEOUT)
      deliver_error! 422, message: "Unable to finalise upload of database older than #{timeout_duration.inspect}"
    end

    validation_error = database.validate_database_contents
    unless validation_error.nil?
      deliver_error! 422, message: validation_error
    end

    saved = database.track_uploaded
    deliver_error! 422, errors: database.errors unless saved
    GitHub.dogstats.increment("code_scanning.codeql_database.uploaded")

    instrument_upload_to_hydro(repo, database.language, database.size)

    # Trigger a job to cleanup any old databases for this repository
    CodeqlDatabaseCleanupJob.perform_later(repository_id: repo.id)

    return deliver :codeql_database_upload_hash, database, status: 200
  end

  get "/repositories/:repository_id/code-scanning/codeql/databases", operation_id: "code-scanning/list-codeql-databases" do
    @route_owner = "@github/code-scanning-secexp"
    @accepted_scopes = %w(repo)

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_codeql_database,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 if repo.hide_from_user?(current_user)
    deliver_error_if_archived! repo

    databases = ActiveRecord::Base.connected_to(role: :reading) do
      CodeqlDatabase.latest_for_repo(repo.id)
    end

    if databases.empty?
      codeql_languages = fetch_codeql_languages(repo.id)
      if codeql_languages.any?
        repos_and_languages = codeql_languages.map { |language| [repo.id, language] }
        CodeqlBulkBuilderOnboardJob.perform_later(repos_and_languages:)
      end
    end

    deliver :codeql_database_array_upload_hash, { databases: databases }, status: 200
  end

  allow_media("application/zip")
  get "/repositories/:repository_id/code-scanning/codeql/databases/:language", operation_id: "code-scanning/get-codeql-database" do
    @route_owner = "@github/code-scanning-secexp"
    @accepted_scopes = %w(repo)

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_codeql_database,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 if repo.hide_from_user?(current_user)

    deliver_error_if_archived! repo

    language = params[:language]
    deliver_error! 400, message: "Language not specified" if language.nil?

    # Find the latest uploaded database
    codeql_database = ActiveRecord::Base.connected_to(role: :reading) do
      CodeqlDatabase.latest_for_repo_and_language(repo.id, language)
    end

    if codeql_database.nil?
      CodeqlBulkBuilderOnboardJob.perform_later(repos_and_languages: [[repo.id, language]])
      deliver_error! 404, message: "No database available for \"#{language}\" yet. Please try again in a bit."
    end

    zip = request.accept.any? { |mime| mime.downcase == Mime[:zip] }
    if zip
      instrument_download_to_hydro(repo, language, codeql_database.size)
      deliver_redirect! codeql_database.url(actor: current_user), status: 302
    else
      deliver :codeql_database_upload_hash, codeql_database, status: 200
    end
  end

  delete "/repositories/:repository_id/code-scanning/codeql/databases/:language", operation_id: "code-scanning/delete-codeql-database" do
    @route_owner = "@github/code-scanning-secexp"
    @accepted_scopes = %w(repo)

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :delete_codeql_database,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error_if_archived! repo

    codeql_databases = CodeqlDatabase.where(repository_id: repo.id, language: params[:language])
    codeql_databases.each(&:destroy)

    deliver_empty({ status: 204 })
  end

  # Scope for a signed auth token valid for uploading a database for the given repository
  def self.signed_auth_token_upload_scope(repository_id)
    "Api::RepositoryCodeScanningDatabases/put/#{repository_id}"
  end

  private

  def repo_path(repo)
    "database/#{repo.id}"
  end

  def database_path(repo, language)
    "#{repo_path(repo)}/#{language}"
  end

  def instrument_upload_to_hydro(repo, language, size)
    GlobalInstrumenter.instrument("code_scanning.codeql_database_upload", {
      repository: repo,
      actor: current_user,
      uploaded_at: Time.now,
      language: language,
      size: size,
    })
  end

  def instrument_download_to_hydro(repo, language, size)
    GlobalInstrumenter.instrument("code_scanning.codeql_database_download", {
      repository: repo,
      actor: current_user,
      downloaded_at: Time.now,
      language: language,
      size: size,
    })
  end

  def fetch_codeql_languages(repo_id)
    language_names = ActiveRecord::Base.connected_to(role: :reading) do
      language_name_ids = Language.where(repository_id: repo_id).pluck(:language_name_id)
      LanguageName.where(id: language_name_ids).pluck(:name)
    end
    CodeqlVariantAnalysis::CODEQL_TO_LINGUIST_LANGUAGES.select do
      |_k, v| v.intersect?(language_names)
    end.keys
  end
end
