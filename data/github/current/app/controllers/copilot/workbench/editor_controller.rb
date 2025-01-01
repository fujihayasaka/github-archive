
# typed: true
# frozen_string_literal: true

class Copilot::Workbench::EditorController < Copilot::Workbench::BaseEditorController

  include GitHub::ResilienceMixin
  include WebCommitControllerMethods

  self.react_bundle_name = "workbench"
  stylesheet_bundle "copilot-markdown-rendering"

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

  def create
    initial_prompt = params[:initialPrompt]
    new_workbench = ::Workbench.create_workbench(current_user.id, "New Workbench", initialPrompt: initial_prompt, shouldGenerateInitialPrompt: true)
    redirect_to spark_show_path(new_workbench[:id])
  end

  def show
    if current_user&.feature_enabled?(:copilot_workbench)
      T.must(request).format = :json if json_request?
      add_client_feature_flag([:hadron_comment_fix_generation])
      add_client_feature_flag([:hadron_terminal_completions])
      add_client_feature_flag([:workspace_editor_fix_a_build_function_calling])
      add_client_feature_flag([:dotcom_chat_client_side_skills])
      add_client_feature_flag([:file_uploading_in_workspace_editor])

      title_start = if is_new_file_path?
        "New file · "
      elsif is_editor_path?
        "#{path_string} · "
      elsif is_overview_path?
        "Overview · "
      else
        ""
      end

      add_csp_exceptions

      render_react_app(
        title: "Spark Workbench - #{workbench["name"]}",
        payload: app_payload,
        app_payload_generator: -> { { markdownDocsUrl: GitHub.markdown_docs_url } },
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
  end

  private

  def app_payload
    path_exists = is_new_file_path? #|| !is_deleted && !!current_blob
    base_payload = base_app_payload(path_exists)
    blob_content = workbench.dig("files", path_string || "index.html")&.dig("content")

    {
      blobContents: blob_content,
      workbench: workbench,
      large: false,
      isBinary: false,
      compareBlobContents: nil,
      editorSettings: {
        **editor_settings
      },
      **current_user_data,
      **base_payload,
    }
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

    repo = Repositories.domain.by_qualified_name("github/workbench-template")
    if repo.nil? && ENV["CODESPACE_NAME"]
      # If in dev, fall back to a known github.localhost repo
      # Won't work for running dev server etc. in workbench, but allows frontend to limp along
      repo = Repositories.domain.by_qualified_name("monalisa/smile")
    end
    repo = T.must(repo)

    {
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
      findFileWorkerPath: find_file_worker_path,
      diffPaths: diff_paths,
      fileStatuses: file_statuses,
      helpUrl: GitHub.help_url,
      copilot: {
        **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, current_user), request),
        ssoOrganizations: sso_organizations,
      },
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

  sig { returns(AssetBundlesHelper) }
  memoize def asset_bundles_helper
    AssetBundlesHelper.new(current_user)
  end

  sig { params(worker: String).returns(String) }
  def find_worker_path(worker)
    name = asset_bundles_helper.expand_bundle_name(worker)
    web_worker_path(name)
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

  def add_csp_exceptions
    csp_exceptions = {
      frame_src: ["*.app.github.dev"],
    }

    SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
  end

  # BaseEditorController expects a current repo which we don't have, so we override here
  def authorized?
    logged_in?
  end
end
