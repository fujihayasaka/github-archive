# typed: true
# frozen_string_literal: true

class RepositoryImportsController < RepositoryImports::BaseController
  REPO_400MB_MAX_OBJECT_SIZE = 400.freeze

  include TradeControlsHelper
  include Repos::OwnerRepoSelectionsPayloadHelper
  include RepositoriesDefaultSelectionHelper
  include ConditionalAccessHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  skip_before_action :ensure_visible_to_user, only: %w(new create)
  skip_before_action :authorization_required, only: %w(new create)
  before_action :login_required, only: :create
  before_action :login_required_with_redirect, only: :new
  before_action :content_authorization_required, only: %w(new create)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :show],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "repo-creation"
  end

  # Public: New repository and import form.
  def new
    add_csrf_token(repository_check_name_path, :post)
    add_client_feature_flag([:github_importer_on_actions], entity: current_organization)

    context_region_title "Import repository"

    tags = ["form:import"]
    tags << "defer_owners_list:#{current_user.organizations.size > Repositories::CreateView::ORG_COUNT_DEFER_LIMIT}"
    payload = GitHub.dogstats.distribution_time("repos_form.payload.time", tags: tags) do
      owner_items = initial_owner_items_payload(cap_filter, current_user)

      initial_owner_selection = initial_owner_or_default_payload(params[:owner], cap_filter, current_user, current_organization)

      {
        repoCreate: Repos::ReactPayload.repo_create_payload(owner_items, cap_filter, current_user),
        initialOwnerSelection: initial_owner_selection,
        privateModeEnabled: GitHub.private_mode_enabled?,
        tradeControlsPrivateRepoCreationWarning: trade_controls_private_repo_creation_warning,
        tradeControlsUserPrivateRepoCreationWarning: trade_controls_user_private_repo_creation_warning,
      }
    end

    render_react_app(
      title: "Import repository",
      payload: payload,
      page_data: { send_vitals: true },
      disable_ssr: !feature_enabled_globally_or_for_current_user?(:repos_forms_ssr),
    )
  end

  # Public: Create repository and start import from source repository.
  def create
    unless params.key?(:repository)
      return render(json: { data: { error: "Whoops! Something went wrong. Please try again." }, code: 422 }, status: :unprocessable_entity)
    end

    parameters = repository_params.to_h.merge auto_init: false

    requested_owner = target_repository_owner

    return render_404 unless requested_owner

    visibility = params[:repository]["visibility"]

    unless requested_owner.can_create_repository?(current_user, visibility: visibility)
      return render(json: { data: { error: "Unable to create repository for #{requested_owner.display_login}." }, code: 422 }, status: :unprocessable_entity)
    end

    if current_user.emu_creating_public_repo?(visibility)
      return render(json: { data: { error: "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility" }, code: 422 }, status: :unprocessable_entity)
    end

    result = Repository.handle_creation(
      current_user,
      requested_owner.login, # rubocop:disable GitHub/DoNotAllowLogin login used for creation
      parameters,
    )

    tags = ["form:import"]
    tags << "public:#{parameters[:public].present? ? "true" : "false"}"
    tags << "error:#{!result.success?}"
    GitHub.dogstats.increment("repos_form_submit", tags: tags)

    return render(json: { data: { error: result.error_message.to_s }, code: 422 }, status: :unprocessable_entity) unless result.success?

    repo = result.repository

    if use_github_importer_on_actions?
      repo.set_max_object_size(REPO_400MB_MAX_OBJECT_SIZE, current_user) if max_object_size_400_mib?

      repository_actions_source_import = RepositoryActionsSourceImport.new(
        user: current_user,
        repository: repo
      )

      begin
        repository_actions_source_import.start_import(
          source_url: params[:vcs_url].strip,
          source_username: params["source_username"].presence,
          source_access_token: params["source_access_token"].presence
        )

        ImportExport.domain.importing_started!(repo)

        GitHub.dogstats.increment("github_importer_on_actions.import.started")

        emit_porter_hydro_event(repo)

        redirect_to repository_import_path(user_id: repo.owner&.login, repository: repo) # rubocop:disable GitHub/DoNotAllowLogin login used to create URL
      rescue GitSrcMigrator::Twirp::Error, Faraday::Error => e
        tags = ["rpc:start_migration", "error:#{e.class}"]
        GitHub.dogstats.increment("github_importer_on_actions.gsm.unavailable", tags: tags)

        # rubocop:disable Style/HashSyntax
        GitHub.logger.error(
          "Failed to start import",
          exception: e,
          "gh.request_id" => GitHub.context[:request_id],
          "code.function" => "create",
          "code.namespace" => "RepositoryImportsController",
        )

        if e.message.include?("Couldn't connect to server")
          return render(json: { data: { error: "GitHub Importer is currently unavailable. Please try again later." }, code: 500 }, status: :internal_server_error)
        end

        render(json: { data: { error: "Whoops! Something went wrong. Please try again later." }, code: 422 }, status: :unprocessable_entity)
      end
    else
      repository_import = RepositorySourceImport.new(
        repository: repo,
        user: current_user,
      )

      begin
        repository_import.start_import(vcs_url: params[:vcs_url].strip)
      rescue Porter::ApiClient::Error
        flash[:error] = "We can't import from #{params[:vcs_url]}. Please check the URL and try again."
      end

      emit_porter_hydro_event(repo) unless flash[:error]

      redirect_to repository_import_path(repository_import.url_params)
    end
  end

  # Public: Show the current state of the import.
  def show
    # Render GSM view if github_importer_on_actions_check_gsm_for_migrations is enabled and a GSM migration exists.
    return render_gsm_show if check_gsm_for_migrations? && repository_actions_source_import.migration_exists?

    # Render GSM view if the github_importer_on_actions feature flag is enabled.
    return render_gsm_show if use_github_importer_on_actions?

    # Render Porter view (if the github_importer_on_actions feature flag is disabled).
    render_porter_no_migration
  end

  # Public: Destroy an existing import and start it again with a new vcs_url or
  # simply restart the import if no vcs_url is provided.
  def update
    if params[:vcs_url]
      begin
        repository_import.stop_import
        repository_import.start_import(vcs_url: params[:vcs_url])
      rescue Porter::ApiClient::Error
        flash[:error] = "We can't import from #{params[:vcs_url]}. Please check the URL and try again."
      end
    else
      # Restart the import.
      repository_import.restart_import
    end

    redirect_to repository_import_path(repository_import.url_params)
  end

  def destroy
    # Stop running import.
    ImportExport.domain.importing_stopped!(repository_import.repository)
    repository_import.stop_import

    # Redirect to repository
    redirect_to repository_path(repository_import.repository)
  end

  private

  def repository_params
    return ActionController::Parameters.new unless params.key?(:repository)
    params.require(:repository).permit %i[name description public visibility]
  end

  def login_required_with_redirect
    redirect_to_login(request&.url) unless logged_in?
  end

  def content_authorization_required
    authorize_content(:repo)
  end

  def show_view_model(flash_message = {})
    create_view_model(
      RepositoryImports::ShowView,
      {
        repository_import: repository_import,
        start_percent: params[:percent],
        start_status: params[:status].to_s,
      }.merge(flash_message)
    )
  end

  def protected_org_logins_payload
    protected_org_ids = T.let(cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml), T::Array[Integer])
    if protected_org_ids.any?
      Organization.find(protected_org_ids).pluck(:login)
    end
  end

  def render_gsm_show
    return render_gsm_no_migration unless repository_actions_source_import.migration_exists?

    channel = live_update_view_channel(GitHub::WebSocket::Channels.source_import(current_repository))

    status, failure_reason, error_details = begin
      gsm_status = repository_actions_source_import.status
      [gsm_status.state.to_s, gsm_status.failure_reason.to_s, gsm_status.error_details]
    rescue GitSrcMigrator::Twirp::Error
      ["", "", []]
    end

    react_payload = { channel: channel, status: status, failure_reason: failure_reason, error_details: error_details }

    render_react_app(
      payload: react_payload,
      title: "#{repository_actions_source_import.repository.name_with_display_owner}: Import",
      app_name: "github-importer",
    )
  end

  def render_gsm_no_migration
    return redirect_to repository_path(repository_actions_source_import.repository) unless repository_actions_source_import.repository.empty?
    redirect_to "/new/import"
  end

  def render_porter_no_migration
    return redirect_to repository_path(repository_import.repository) unless repository_import.repository.empty?

    @owner = current_organization || current_user
    @repository = current_repository
    render "repository_imports/new",
      locals: { view: show_view_model },
      layout: !request&.xhr?
  end

  def check_gsm_for_migrations?
    current_user.feature_enabled?(:github_importer_on_actions_check_gsm_for_migrations)
  end

  def use_github_importer_on_actions?
    current_user.feature_enabled?(:github_importer_on_actions)
  end

  def max_object_size_400_mib?
    current_user.feature_enabled?(:octoshift_imports_max_object_size_400mb)
  end

  def emit_porter_hydro_event(repo)
    if current_user.feature_enabled?(:porter_import_created_hydro_event)
      GlobalInstrumenter.instrument("porter.import_created", {
        oauth_application_id: nil,
        repository_id: repo.id,
        source: :ui
      })
    end
  end
end
