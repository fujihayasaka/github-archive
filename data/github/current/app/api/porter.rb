# typed: true
# frozen_string_literal: true

class Api::Porter < Api::App
  include ReceiveSchemaWithOpenApi

  MAINTENANCE_MODE_MESSAGE = "Import API is currently in maintenance mode. Please try again later."

  before do
    deliver_error!(404) unless GitHub.porter_available?
    deliver_error!(503, message: MAINTENANCE_MODE_MESSAGE) if GitHub.porter_maintenance_mode?

    deprecated(
      deprecation_date: Time.utc(2024, 4, 12),
      sunset_date: Time.utc(2024, 4, 12),
      info_url: "https://github.blog/changelog/2023-10-12-deprecation-source-imports-rest-api/",
      alternate_path_url: ""
    )

    deliver_error!(404, message: "This endpoint has been deprecated. To import a repository, please use the GitHub Importer tool at https://github.com/new/import.") if deprecate_source_imports_api_enabled?
  end

  CustomErrors = {
    Porter::ApiClient::ErrorRateLimit::Error => "error_rate_limit".freeze,
    Porter::ApiClient::ClientRequestLimit::Error => "internal_request_limit".freeze,
    Faraday::TimeoutError => "timeout_error".freeze,
  }.freeze

  CustomErrors.keys.each do |error_class|
    error error_class do
      if code = CustomErrors[env["sinatra.error"].class]
        @meta["X-GitHub-Error-Class"] = code
        GitHub.dogstats.increment "porter", tags: ["via:api", "status:503", "code:#{code}"]
      end
      deliver_error!(503, message: "The import API is temporarily unavailable.")
    end
  end

  # start an import
  put "/repositories/:repository_id/import", operation_id: "migrations/start-import" do
    control_access :manage_import_writer, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    deliver_error!(422, message: "Importing into a repository with actions enabled is currently not supported. Please disable actions and try again.") if current_repo.actions_enabled?
    deliver_error!(403, message: "User must have workflow scope in order to import a repository.") if !user_has_workflow_autorization?

    # Introducing strict validation of the import.start
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("import", "start", skip_validation: true)

    proxy_errors do
      response = porter.start_import(data)

      GlobalInstrumenter.instrument("porter.import_created", {
        oauth_application_id: GitHub.context[:oauth_application_id],
        repository_id: repo.id,
        source: :api
      }) if FeatureFlag.vexi.enabled?(:porter_import_created_hydro_event, current_user, default: true)

      ImportExport.domain.importing_started!(current_repo)

      deliver :porter_import_hash, response, repo: repo,
        # Porter responds with 201 or 200, depending on whether the import is new or was already present.
        status: porter.last_response.status
    end
  end

  # stop an import
  delete "/repositories/:repository_id/import", operation_id: "migrations/cancel-import" do
    receive_with_schema("import", "delete")

    control_access :manage_import_writer, resource: find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    proxy_errors do
      porter.stop_import

      ImportExport.domain.importing_stopped!(current_repo)

      deliver_empty(status: 204)
    end
  end

  # get import progress
  get "/repositories/:repository_id/import", operation_id: "migrations/get-import-status" do
    control_access :manage_import_reader, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    proxy_errors do
      response = porter.import_status
      deliver :porter_import_hash, response, repo: repo
    end
  end

  # get the author list
  get "/repositories/:repository_id/import/authors", operation_id: "migrations/get-commit-authors" do
    control_access :manage_import_reader, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    proxy_errors do
      response = porter.authors(params.slice("since"))
      deliver :porter_author_hash, response, repo: repo
    end
  end

  # set the mapped author information
  patch "/repositories/:repository_id/import/authors/:author_id", operation_id: "migrations/map-commit-author" do
    control_access :manage_import_writer, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    data = receive_with_schema("import", "update-author")

    proxy_errors do
      response = porter.update_author(params[:author_id], data)

      deliver :porter_author_hash, response, repo: repo
    end
  end

  # "yes, use git-lfs to push my large files"
  # or
  # "no, do not use git-lfs on this project"
  patch "/repositories/:repository_id/import/lfs", operation_id: "migrations/set-lfs-preference" do
    control_access :manage_import_writer, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    data = receive(Hash, required: false) || {}

    # Fill in missing data.
    data["committer"] ||= {}
    data["committer"]["name"] ||= current_user.git_author_name
    data["committer"]["email"] ||= current_user.git_author_email
    data["committer"]["time"] ||= Time.now.to_i
    data["committer"]["time_offset"] ||= current_user.time_zone.utc_offset

    proxy_errors do
      response = porter.set_lfs_preference(data)

      # Introducing strict validation of the import.update-lfs-preference
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      _ = receive_with_schema("import", "update-lfs-preference", skip_validation: true)

      deliver :porter_import_hash, response, repo: repo
    end
  end

  # restart import or update auth/project choice for existing import
  patch "/repositories/:repository_id/import", operation_id: "migrations/update-import" do
    control_access :manage_import_writer, resource: repo = find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    data = receive_with_schema("import", "update")

    proxy_errors do
      response = porter.update_import(data)

      deliver :porter_import_hash, response, repo: repo,
        # Porter responds with 200 because the import was already present.
        status: porter.last_response.status
    end
  end

  # get the large files list
  get "/repositories/:repository_id/import/large_files", operation_id: "migrations/get-large-files" do
    control_access :manage_import_reader, resource: find_repo!, allow_integrations: false, allow_user_via_granular_actor: true

    proxy_errors do
      response = porter.large_files(pagination)
      deliver :porter_large_files_hash, response["entries"]
    end
  end

  private

  # An API client for porter.
  def porter
    @porter ||=
      Porter::ApiClient.new \
        current_user: current_user,
        current_repository: find_repo,
        set_import_started: false,
        send_import_status: false,
        site_admin: Api::Serializer.instance_admin?(current_user, viewer: current_user)
  end

  # Rescue errors and deliver an appropriate error.
  def proxy_errors
    yield
  rescue Porter::ApiClient::Error => e
    if e.status >= 500
      Failbot.report!(e)
    end
    if e.status == 429
      deliver_error! 403, message: "Rate Limit Exceeded"
    elsif message = e.public_error_message
      deliver_error! e.status, message: message
    else
      deliver_error! e.status
    end
  end

  def user_has_workflow_autorization?
    current_user.oauth_access?("workflow")
  end

  def deprecate_source_imports_api_enabled?
    current_user.present? ? current_user.feature_flag_enabled?(:import_export_deprecate_source_imports_api, default: true) : FeatureFlag.vexi.enabled?(:import_export_deprecate_source_imports_api, default: true)
  end
end
