# typed: true
# frozen_string_literal: true

class Copilot::Workbench::EditorController < Copilot::Workbench::AbstractWorkbenchController
  include GitHub::ResilienceMixin
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include MonacoMethods

  self.react_bundle_name = "workbench"
  stylesheet_bundle "copilot-markdown-rendering"

  CSP_EXCEPTIONS = {
    frame_src: Rails.env.development? ? ["*.app.github.dev", "github.dev", "*.dev.github.dev", "dev.github.dev", "*.github.app"] : ["*.app.github.dev", "github.dev", "*.github.app"],
    connect_src: [
      "https://*.github.dev",
      "https://github.dev",
      "https://*.app.github.dev",
      "https://*.github.app",
      "*.blob.core.windows.net", # TODO: set specific storage account
    ],
    form_action: ["https://*.github.dev", "https://*.github.app"]
  }

  allow_verified_fetch

  before_action :try_parse_json_params
  before_action :add_workbench_csp_exceptions, only: [:show, :create]

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
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
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

    if current_user&.feature_enabled?(:copilot_workbench_session_snapshot)
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
      event_data: {
        action: "create",
        has_initial_prompt: initial_prompt.present?,
        runtime_app_id: runtime_app_id
      },
      event_time: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
      event_type: "workbench.create",
      request_id: request.request_id || "",
      session_id: request.session.id.to_s || "",
      spark_id: new_workbench[:id],
      user_analytics_tracking_id: current_user.analytics_tracking_id,
      user_id: current_user.id,
      restricted: false
    )
    Workbench::WorkbenchAnalyticsEvent.workbench_event(analytics_payload)
    respond_to do |format|
      format.html do
        if feature_enabled_globally_or_for_current_user?(:spark_workbench_updated_urls)
          redirect_to spark_friendly_path(current_user.display_login, new_workbench[:id], initialPrompt: initial_prompt)
        else
          redirect_to spark_show_path(new_workbench[:id], initialPrompt: initial_prompt)
        end
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
    :copilot_workbench_connection_reload_banner,
    :copilot_workbench_read_only_preview,
    :copilot_workbench_reconnect_on_focus,
    :spark_verify_preview_auth_without_redirect,
    :spark_auto_fix_empty_app,
    :spark_workbench_updated_urls,
    :copilot_workbench_rich_ai_prompt_parsing,
    :spark_use_deploy_script_from_sdk,
  ]

  def show
    if current_user&.spark_workbench_preview_enabled?
      T.must(request).format = :json if json_request?
      add_client_feature_flag(DEFAULT_CLIENT_FEATURE_FLAGS)

      # Due to how we store the workbench object vs present it publicly, we need to check for the existence
      # of `runtimePermanentName`, but save it has `runtime_app_id`. It wil then later populate the name.
      if workbench[:runtimePermanentName].nil?
        runtime_app = ::SparkRuntimeApp.create_runtime_app(current_user)
        workbench[:runtime_app_id] = runtime_app[:app_id]
        workbench[:runtimePermanentName] = runtime_app[:permanent_name]
        ::Workbench::save_workbench(current_user.id, workbench[:id], JSON.dump(workbench))
      end

      # This typically gets created when we make the runtime app, but because
      # we had Sparks before it existed patch it up here. At some point this
      # can probably be removed once all Sparks have generated an app owner.
      SparkRuntime::AppOwner.ensure_owner(current_user)

      if current_user&.feature_enabled?(:copilot_workbench_session_snapshot)
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
        title: "#{workbench["name"]} · Spark",
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
    else
      render_404
    end
  rescue TypeError
    render_404
  end

  private

  def app_payload
    path_exists = is_new_file_path? #|| !is_deleted && !!current_blob
    base_payload = base_app_payload(path_exists)


    deploy = {}
    runtime_app = T.must(Spark::RuntimeApp.find_by(permanent_name: workbench["runtimePermanentName"]))
    last_deploy = runtime_app.runtime_app_deploys.where(display_name: "").last
    if last_deploy
      deploy = {
        deploy: {
          createdAt: last_deploy.created_at,
          deployLogin: runtime_app.username,  # May not match current user!
          displayName: last_deploy.display_name,
          domainBase: "github.app",           # Will have logic soon so building in
          revision: last_deploy.revision,
        }
      }
    end

    payload = {
      workbench: workbench,
      large: false,
      isBinary: false,
      compareBlobContents: nil,
      deploymentVisibility: runtime_app.visibility,
      friendlyName: runtime_app.friendly_name,
      login: current_user&.display_login,
      editorSettings: {
        **editor_settings
      },
      **deploy,
      **current_user_data,
      **base_payload,
    }

    if current_user&.feature_enabled?(:copilot_workbench_session_snapshot)
      snapshot_upload_uri = Workbench::SnapshotBlobs.get_snapshot_upload_uri(workbench[:id])
      payload[:snapshotUploadUri] = snapshot_upload_uri if snapshot_upload_uri
    end

    if current_user&.feature_enabled?(:copilot_workbench_read_only_preview)
      preview_deploy_app = runtime_app.runtime_app_deploys.find_by(display_name: "spark-preview")
      if preview_deploy_app
        preview_deploy = {
          createdAt: preview_deploy_app.created_at,
          deployLogin: runtime_app.username,
          displayName: preview_deploy_app.display_name,
          domainBase: "github.app",
          revision: preview_deploy_app.revision,
        }

        payload[:previewDeploy] = preview_deploy

        encrypted_app_token = SparkRuntime::AcaTokenService.mint_encrypted_jwt(
            app_name: runtime_app.permanent_name,
            app_owner_login: current_user.display_login,
            user_session: user_session)
        at_hash = SparkRuntime::AcaTokenService.token_at_hash(encrypted_app_token)
        aca_jwt = SparkRuntime::AcaJwtGenerator.new(
          runtime_app.permanent_name,
          current_user.display_login,
          GitHub.copilot_workbench_aca_jwt_private_key,
          at_hash).jwt

        payload[:acaJwtInfo] = {
          payload: aca_jwt,
          proxyPayload: encrypted_app_token,
          appName: runtime_app.permanent_name,
          userLogin: current_user.display_login,
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
      workbench["initialPrompt"] = params[:initialPrompt]
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
    if current_user&.feature_enabled?(:copilot_workbench_monaco_wasm)
      exceptions[:script_src] = ["'wasm-unsafe-eval'"]
      exceptions[:connect_src] += [GitHub.asset_host_url]
    end
    SecureHeaders.append_content_security_policy_directives(request, exceptions)
  end
end
