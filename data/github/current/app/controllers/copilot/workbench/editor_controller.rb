# typed: true
# frozen_string_literal: true

class Copilot::Workbench::EditorController < Copilot::Workbench::AbstractWorkbenchController
  include GitHub::ResilienceMixin
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include MonacoMethods

  self.react_bundle_name = "workbench"
  stylesheet_bundle "copilot-markdown-rendering"

  snapshot_storage_account = "sparkworkbench"

  frame_src_domains = ["blob:", "*.app.github.dev", "github.dev", "*.github.app", "*.users.github.app"]
  frame_src_domains_dev = frame_src_domains + ["*.dev.github.dev", "dev.github.dev"]
  connect_src_domains = [
      "https://*.github.dev",
      "https://github.dev",
      "https://*.app.github.dev",
      "https://*.github.app",
      "https://*.users.github.app",
      "#{snapshot_storage_account}.blob.core.windows.net",
      "https://scanning-api.github.com", # secret scanning public API
  ]
  connect_src_domains_dev = connect_src_domains + [
    "http://localhost:5001" # secret scanning public API (dev)
  ]

  CSP_EXCEPTIONS = {
    frame_src: Rails.env.development? ? frame_src_domains_dev : frame_src_domains,
    connect_src: Rails.env.development? ? connect_src_domains_dev : connect_src_domains,
    form_action: ["https://*.github.dev", "https://*.github.app", "https://*.users.github.app"],
    media_src: ["blob:"],
    object_src: ["blob:"],
  }

  allow_verified_fetch

  before_action :try_parse_json_params
  before_action :add_workbench_csp_exceptions, only: [:show, :create]
  before_action :require_owner, only: [:show]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    only: [:create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w(
    Copilot::Workbench::EditorController#create
    FilesController#disamgiguate
  )

  def create
    initial_prompt = params[:initialPrompt]

    runtime_app = ::SparkRuntimeApp.create_runtime_app(current_user)
    runtime_app_id = runtime_app[:app_id]

    new_workbench = ::Workbench.create_workbench(current_user.id, runtime_app_id, "New spark", initialPrompt: initial_prompt, shouldGenerateInitialPrompt: true)

    if current_user&.feature_flag_enabled?(:copilot_workbench_session_snapshot, default: false)
      begin
        Workbench::SnapshotBlobs.create_container_if_not_exists(new_workbench[:id])
      rescue Azure::Core::Http::HTTPError => e
        GitHub.logger.error("Failed to create blob container",
          "gh.error.message" => e.message,
          "gh.error.status_code" => e.status_code,
          "gh.workbench.id" => new_workbench[:id],
          "gh.user.id" => current_user.id
        )
      end
    end

    # Track workbench creation event
    analytics_payload = Workbench::TelemetryInstrumenter::Payload.new(
      context: {
        runtime_permanent_name: runtime_app[:permanent_name],
        create_source: params[:createSource],
        file_types: params[:fileTypes],
        files_attached: params[:filesAttached],
        num_files: params[:numFiles],
        prompt_length: params[:promptLength],
        staff: current_user.employee?
      },
      event_time: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
      event_type: "workbench.create",
      request_id: request_id || "",
      session_id: request.session.id.to_s || "",
      spark_id: new_workbench[:id],
      user_analytics_tracking_id: current_user.analytics_tracking_id,
      user_id: current_user.id,
      restricted: false,
    )
    Workbench::WorkbenchAnalyticsEvent.workbench_event(analytics_payload)
    respond_to do |format|
      format.html do
        redirect_to spark_friendly_path(current_user.display_login, new_workbench[:id], initialPrompt: initial_prompt)
      end

      format.json do
        render json: {
          id: new_workbench[:id],
          billableOwner: new_workbench[:billable_owner],
        }
      end
    end
  end

  DEFAULT_CLIENT_FEATURE_FLAGS = [
    :workbench_copilot_lsp_v2,
    :copilot_workbench_session_snapshot,
    :spark_overlay_on_empty,
    :copilot_workbench_refresh_on_wsod,
    :copilot_workbench_preview_area_v2,
    :copilot_workbench_connection_reload_banner,
    :copilot_workbench_read_only_preview,
    :copilot_workbench_reconnect_on_focus,
    :spark_auto_fix_empty_app,
    :copilot_workbench_rich_ai_prompt_parsing,
    :spark_force_push_after_checkout,
    :spark_create_manual_iteration_on_file_edit,
    :spark_pull_from_repository,
    :spark_assets_include_media,
    :workspace_resume_from_blob,
    :spark_check_rehydrate_completed,
    :spark_static_preview,
    :spark_check_root_element_empty_for_preview,
    :spark_fix_free_quotas,
    :spark_log_rate_limit_event,
    :copilot_spark_show_repo_url,
    :spark_kv_shortcut_reads,
    :spark_prompt_secret_scanning,
  ].freeze

  preload_features DEFAULT_CLIENT_FEATURE_FLAGS, only: [:show, :create]

  def show
    render_404 and return unless current_user&.spark_workbench_preview_enabled?

    T.must(request).format = :json if json_request?
    add_client_feature_flag(DEFAULT_CLIENT_FEATURE_FLAGS)

    # This typically gets created when we make the runtime app, but because
    # we had Sparks before it existed patch it up here. At some point this
    # can probably be removed once all Sparks have generated an app owner.
    SparkRuntime::AppOwner.ensure_owner(current_user)

    if current_user&.feature_flag_enabled?(:copilot_workbench_session_snapshot, default: false)
      begin
        Workbench::SnapshotBlobs.create_container_if_not_exists(workbench[:id])
      rescue Azure::Core::Http::HTTPError => e
        GitHub.logger.error("Failed to create blob container",
          "gh.error.message" => e.message,
          "gh.error.status_code" => e.status_code,
          "gh.workbench.id" => workbench[:id],
          "gh.user.id" => current_user.id
        )
      end
    end

    render_react_app(
      title: "#{workbench[:name]} · Spark",
      payload: app_payload,
      app_payload_generator: -> {
        {
          markdownDocsUrl: GitHub.markdown_docs_url,
          monacoWorkerUrls: monaco_worker_paths(method(:web_worker_url)),
          **copilot_data,
        }
      },
      page_data: {
        hide_footer: true,
        hide_header_content: true,
        # prevents body element from scrolling - we'll handle scrolling in the app
        class: "overflow-hidden"
      },
      layout: "application",
      disable_ssr: true, # can revisit in the future, but if we're showing monaco not sure SSR accomplishes much
    )

  rescue TypeError
    render_404
  rescue => e
    GitHub.logger.error("Error rendering workbench editor",
      "gh.error.message" => e.message,
      "gh.error.class" => e.class.name,
      "gh.error.backtrace" => T.must(e.backtrace).join("\n"),
      "gh.workbench.id" => workbench[:id],
      "gh.user.id" => current_user.id
    )
    render_404
  end

  private

  def app_payload
    path_exists = is_new_file_path? #|| !is_deleted && !!current_blob
    base_payload = base_app_payload(path_exists)

    deploy = {}
    runtime_app = T.must(Spark::RuntimeApp.find_by(permanent_name: workbench.dig(:runtime, :app, :permanentName)))
    last_deploy = runtime_app.runtime_app_deploys.where.not(display_name: "spark-preview").last
    if last_deploy
      deploy = {
        deploy: {
          createdAt: last_deploy.created_at,
          deployLogin: runtime_app.runtime_app_owner.deploy_login,
          displayName: last_deploy.display_name,
          domainBase: runtime_app.runtime_app_owner.deployment_domain_base,
          revision: last_deploy.revision,
        }
      }
    end

    payload = {
      workbench: workbench,
      large: false,
      isBinary: false,
      compareBlobContents: nil,
      login: current_user.display_login,
      userAnalyticsTrackingId: current_user.analytics_tracking_id,
      organizations: user_organizations,
      editorSettings: {
        **editor_settings
      },
      **deploy,
      **current_user_data,
      **base_payload,
    }

    if current_user&.feature_flag_enabled?(:copilot_workbench_session_snapshot, default: false)
      snapshot_upload_uri = Workbench::SnapshotBlobs.get_snapshot_upload_uri(workbench[:id], current_user: current_user)
      payload[:snapshotUploadUri] = snapshot_upload_uri if snapshot_upload_uri
    end

    if current_user&.feature_flag_enabled?(:spark_pull_from_repository, default: false)
      payload[:repositoryChannel] = repository_channel
    end

    if current_user&.feature_flag_enabled?(:copilot_workbench_read_only_preview, default: false)
      preview_deploy_app = runtime_app.runtime_app_deploys.find_by(display_name: "spark-preview")
      if preview_deploy_app
        preview_deploy = {
          createdAt: preview_deploy_app.created_at,
          deployLogin: runtime_app.runtime_app_owner.deploy_login,
          displayName: preview_deploy_app.display_name,
          domainBase: runtime_app.runtime_app_owner.deployment_domain_base,
          revision: preview_deploy_app.revision,
        }

        payload[:previewDeploy] = preview_deploy

        encrypted_jwt, token_expires_at = SparkRuntime::TokenService.encrypted_aca_jwt(
          user_session: user_session,
          app_name: runtime_app.permanent_name,
          app_owner_login: current_user.display_login,
        )

        at_hash = SparkRuntime::TokenService.token_at_hash(encrypted_jwt)
        aca_jwt = SparkRuntime::AcaJwtGenerator.new(
          runtime_app.permanent_name,
          current_user.display_login,
          GitHub.copilot_workbench_aca_jwt_private_key,
          at_hash,
          token_expires_at).jwt

        payload_user = if FeatureFlag.vexi.enabled?(:copilot_workbench_auth_redirect_user_param, current_user, default: false)
          SparkRuntime::OwnerApiKV.is_new_api_version?(runtime_app.runtime_app_owner.permanent_name) ? runtime_app.runtime_app_owner.permanent_name : runtime_app.runtime_app_owner.deploy_login
        else
          current_user.display_login
        end

        payload[:acaJwtInfo] = {
          payload: aca_jwt,
          proxyPayload: encrypted_jwt,
          appName: runtime_app.permanent_name,
          userLogin: payload_user,
        }
      end
    end

    payload
  end

  def base_app_payload(path_exists = true)
    file_statuses = {}
    pr_file_statuses, diff_paths = [{}, {}] # async_pull_request_tree_data.sync

    file_tree, file_tree_processing_time, folders_to_fetch = [{}, {}, {}]

    tree_expanded = current_user.settings.get(:copilot_tree_view_expanded)
    show_diff = current_user.settings.get(:copilot_show_diff)
    copilot_access_allowed = with_database_error_fallback(fallback: false) do
      Copilot::Public::User.new(current_user).has_copilot_access?
    end

    template_repo_name = "github/spark-template"

    repo = Repositories.domain.by_qualified_name(template_repo_name)
    if repo.nil? && ENV["CODESPACE_NAME"]
      # If in dev, fall back to a known github.localhost repo
      # Won't work for running dev server etc. in workbench, but allows frontend to limp along
      repo = Repositories.domain.by_qualified_name("monalisa/smile")
    end

    # NOTE: Must downcast because IRepository doesn't have blob method
    repo = T.cast(repo, Repository) # rubocop:disable GitHub/AvoidCast
    blob = repo.blob(repo.default_oid, path_string) if path_string.present?

    {
      blobContents: blob&.data,
      fileTree: file_tree,
      fileTreeProcessingTime: file_tree_processing_time,
      foldersToFetch: folders_to_fetch,
      path: path_string,
      repo: {
        id: repo.id,
        defaultBranch: repo.default_branch,
        name: repo.name,
        ownerLogin: repo.owner_display_login,
        currentUserCanPush: false,
        isFork: repo.fork?,
        isEmpty: false,
        createdAt: repo.created_at,
        ownerAvatar: User::AvatarList.default_image_url("gravatar-user-420"),
        public: repo.public?,
        private: repo.private?,
        isOrgOwned: false,
      },
      copilotAccessAllowed: copilot_access_allowed,
      findFileWorkerPath: helpers.find_file_worker_path,
      diffPaths: diff_paths,
      fileStatuses: file_statuses,
      helpUrl: GitHub.help_url,
      copilot: copilot_data,
      showOverview: is_overview_path?,
      treeExpanded: tree_expanded,
      showDiff: show_diff,
      isNewFilePage: is_new_file_path?,
    }
  end

  def current_user_data
    return {} unless current_user
    {
      currentUser: {
        isStaff: current_user.employee?,
      }
    }
  end

  def user_organizations
    return [] unless current_user

    current_user.organizations.limit(100).map do |org|
      {
        id: org.id,
        login: org.display_login,
        name: org.name,
        primaryAvatarUrl: org.primary_avatar_url
      }
    end
  end

  def copilot_data
    {
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, current_user), request),
      ssoOrganizations: sso_organizations,
    }
  end

  sig { params(worker: String).returns(String) }
  def find_worker_path(worker)
    web_worker_url(worker)
  end

  def editor_settings
    {
      codeLineWrapEnabled: current_user.settings.get(:code_line_wrap_enabled),
      whitespaceHidden: current_user.settings.get(:hadron_whitespace_hidden),
      problemsHidden: current_user.settings.get(:hadron_problems_hidden),
    }
  end

  def is_editor_path?
    path_string.present? || is_new_file_path?
  end

  memoize def is_new_file_path?
    request&.path&.ends_with?("/edit/new")
  end

  def is_overview_path?
    !is_editor_path?
  end

  memoize def workbench
    workbench = T.must(::Workbench.load_workbench(current_user.id, params[:id]))
    # The initial prompt is stored as part of the workbench object payload, so we store it here for now
    if params[:initialPrompt].present?
      workbench[:initialPrompt] = params[:initialPrompt]
    end
    workbench
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  memoize def sso_organizations
    orgs = Organization.where(id: saml_for_user.protected_organization_ids)

    orgs.map do |org|
      {
        id: org.id.to_s,
        login: org.display_login,
        avatarUrl: org.primary_avatar_url
      }
    end
  end

  sig { params(cap_filter: ConditionalAccess::Web::Filter, user: User).returns(T::Array[Organization]) }
  def saml_authorized_organizations(cap_filter, user)
    result_set = cap_filter.authorized(user.organizations, only: :saml)
    result_set.results.map { |r| r.resource }
  end

  def add_workbench_csp_exceptions
    exceptions = self.class.const_get(:CSP_EXCEPTIONS)
    if current_user&.feature_flag_enabled?(:copilot_workbench_monaco_wasm, default: false)
      exceptions[:script_src] = ["'wasm-unsafe-eval'"]
      exceptions[:connect_src] += [GitHub.asset_host_url]
    end
    SecureHeaders.append_content_security_policy_directives(request, exceptions)
  end

  def repository_channel
    return unless workbench[:repository_id]
    repository = T.cast(Repositories.domain.by_id(workbench[:repository_id]), T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
    return unless repository

    GitHub::WebSocket::Channels.signed_branch(repository, repository.default_branch)
  end

  def require_owner
    render_404 if params[:owner] && current_user&.display_login != params[:owner]
  end
end
