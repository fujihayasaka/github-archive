
# typed: true
# frozen_string_literal: true

class Copilot::Workbench::IndexController < Copilot::Workbench::BaseEditorController
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

  def show
    if current_user&.feature_enabled?(:copilot_workbench)
      # Later PR view!
      redirect_to spark_new_path
    else
      render_404
    end
  end

  private

  def app_payload
    Promise.all([async_pull_request_tree_data, async_start_oid]).then do |pull_request_tree_data, start_oid|
      file_statuses, _ = pull_request_tree_data
      end_oid = pull.head_sha
      is_deleted = T.must(file_statuses)[path_string] == "D"

      if !path_string.empty? && end_oid && start_oid
        current_blob = is_deleted ? nil : current_repository.blob(end_oid, path_string, blob_limits)
        if compare_ref.present?
          compare_ref_object = current_repository.refs.find(compare_ref)
          compare_oid = compare_ref_object&.target_oid
          compare_blob = current_repository.blob(compare_oid, path_string, blob_limits) if compare_oid
        end
      end

      path_exists = is_new_file_path? || !is_deleted && !!current_blob
      base_payload = base_app_payload(path_exists)

      {
        blobContents: current_blob&.data,
        large: current_blob&.large?,
        isBinary: current_blob&.binary?,
        compareBlobContents: compare_blob&.data,
        pullRequestNumber: pull.number,
        pullRequest: {
          **base_pull_request_data
        },
        editorSettings: {
          **editor_settings
        },
        **current_user_data,
        **base_payload,
      }
    end.sync
  end

  def base_app_payload(path_exists = true)
    file_statuses = {}
    pr_file_statuses, diff_paths = async_pull_request_tree_data.sync

    # Don't load file statuses for the head ref since we'd just be diffing against the same ref
    # Don't load file statuses for the base ref since we already have those file statuses in pr_file_statuses
    # In both of these cases just return the PR file statuses
    if compare_ref_param.present? && compare_ref_param != pull.head_ref && compare_ref_param != pull.base_ref
      comparison = GitHub::Comparison.from_range_or_ref(current_repository, "#{compare_ref_param}..#{pull.head_ref}", limit: 250, user: current_user)
      comparison.set_diff_options(
        top_only:          true,
        use_summary:       true,
        ignore_whitespace: false,
      )
      diff = comparison.diffs
      diff.deltas.each do |delta|
        file_statuses[delta.path] = delta.status
      end
    else
      file_statuses = pr_file_statuses
    end

    set_form_commit
    web_commit_info = web_commit_info(pull.head_sha, "", pull.head_ref)
    file_tree, file_tree_processing_time, folders_to_fetch = helpers.ascend_tree(
      RepositoryPath.new(path_string || ""),
      pull.head_ref,
      path_exists || is_overview_path?
    )

    tree_expanded = current_user.settings.get(:copilot_tree_view_expanded)
    show_diff = current_user.settings.get(:copilot_show_diff)
    copilot_access_allowed = with_database_error_fallback(fallback: false) do
      Copilot::Public::User.new(current_user).has_copilot_access?
    end

    {
      fileTree: file_tree,
      fileTreeProcessingTime: file_tree_processing_time,
      foldersToFetch: folders_to_fetch,
      path: path_string,
      refInfo: {
        name: pull.head_ref,
        listCacheKey: helpers.ref_list_cache_key,
        canEdit: helpers.can_edit?,
        refType: "branch",
        currentOid: pull.head_sha
      },
      repo: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      copilotAccessAllowed: copilot_access_allowed,
      findFileWorkerPath: find_file_worker_path,
      diffPaths: diff_paths,
      fileStatuses: file_statuses,
      webCommitInfo: web_commit_info,
      helpUrl: GitHub.help_url,
      copilot: {
        **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, current_user), request),
        ssoOrganizations: sso_organizations,
        currentTopic: helpers.repo_props(repo: current_repository, ref_name: pull.head_ref),
      },
      compareRef: compare_ref,
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

  def base_pull_request_data
    {
      id: pull.id,
      number: pull.number,
      title: pull.title,
      headBranch: pull.head_ref,
      headSHA: pull.head_sha,
      baseBranch: pull.base_ref,
      isOpen: pull.open?,
      authorLogin: pull.user.display_login,
    }
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

  memoize def compare_ref
    if compare_ref_param.blank?
      pull.base_ref
    else
      compare_ref_param
    end
  end

  memoize def compare_ref_param
    params[:compare_ref]
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
end
