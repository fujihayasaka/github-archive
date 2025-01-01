# typed: true
# frozen_string_literal: true

class Copilot::TaskController < Copilot::TaskControllerBase
  extend T::Sig
  include BranchesHelper
  include CopilotAuthHelper
  include CopilotChatHelper
  include ReactHelper
  include Repos::TreePayloadHelper
  include GitHub::ResilienceMixin
  include WebCommitControllerMethods

  @react_bundle_name = "copilot-task"

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
    if current_user&.hadron_editor_preview_enabled?
      if !is_editor_path?
        _, diff_paths = async_pull_request_tree_data.sync
        first_file_path = find_first_file(diff_paths, diff_paths.keys[0])
        redirect_to repo_copilot_task_edit_path(id: params[:id], path: first_file_path, show_overview: true)
        return
      end
      T.must(request).format = :json if json_request?
      add_client_feature_flag(:copilot_hadron_suggestions_ui)
      add_client_feature_flag(:hadron_comment_fix_generation)
      add_client_feature_flag(:hadron_terminal_completions)
      title_start = if is_new_file_path?
        "New file · "
      elsif is_editor_path?
        "#{path_string} · "
      else
        ""
      end


      render_react_app(
        title: "#{title_start}Editor · #{pull.title} by #{pull.user.display_login} · Pull Request ##{pull.number}",
        payload: app_payload,
        page_data: {
          hide_footer: true,
          hide_header_content: true,
          # prevents body element from scrolling - we'll handle scrolling in the app
          class: "overflow-hidden"
        },
        layout: "application",
        ssr: false, # can revisit in the future, but if we're showing monaco not sure SSR accomplishes much
      )
    else
      render_404
    end
  end

  private

  def find_first_file(diff_paths, directory)
    value = diff_paths[directory]
    return nil unless value
    value[:items].each do |item|
      if item[:contentType] == :file
        return item[:path]
      elsif item[:contentType] == :directory
        result = find_first_file(diff_paths, item[:path])
        return result if result
      end
    end
    nil
  end

  def app_payload
    Promise.all([async_pull_body_html, async_pull_request_tree_data, async_start_oid]).then do |pull_body_html, pull_request_tree_data, start_oid|
      file_statuses, _ = pull_request_tree_data
      end_oid = pull.head_sha
      is_deleted = T.must(file_statuses)[path_string] == "D"

      if !path_string.empty? && end_oid && start_oid
        blob_oid = is_deleted ? start_oid : end_oid
        current_blob = current_repository.blob(blob_oid, path_string, blob_limits)
        if params[:compare_ref].present?
          compare_ref = current_repository.refs.find(params[:compare_ref])
          compare_oid = compare_ref&.target_oid
          compare_blob = current_repository.blob(compare_oid, path_string, blob_limits) if compare_oid
        end
      end

      path_exists = is_new_file_path? || (!is_deleted && !!current_blob)
      base_payload = base_app_payload(path_exists)

      {
        blobContents: current_blob&.data,
        blobLanguage: current_blob&.language&.name&.downcase,
        compareBlobContents: compare_blob&.data,
        pullRequest: {
          baseBranch: pull.base_ref,
          bodyHtml: pull_body_html,
          labels: labels,
          titleHtml: GitHub::Goomba::TitleMarkdownFilter.call(pull.title),
          **base_pull_request_data
        },
        **focused_task_data,
        **base_payload,
      }
    end.sync
  end

  def base_app_payload(path_exists = true)
    file_statuses = {}
    _, diff_paths = async_pull_request_tree_data.sync
    if params[:compare_ref].present?
      comparison = GitHub::Comparison.from_range_or_ref(current_repository, "#{params[:compare_ref]}..#{pull.head_ref}", limit: 250, user: current_user)
      comparison.set_diff_options(
        top_only:          true,
        use_summary:       true,
        ignore_whitespace: false,
      )
      diff = comparison.diffs
      diff.deltas.each do |delta|
        file_statuses[delta.path] = delta.status
      end
    end

    set_form_commit
    web_commit_info = web_commit_info(pull.head_sha, "", tree_name)

    file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(
      RepositoryPath.new(path_string || ""),
      pull.head_ref,
      path_exists
    )

    {
      fileTree: file_tree,
      fileTreeProcessingTime: file_tree_processing_time,
      foldersToFetch: folders_to_fetch,
      path: path_string,
      refInfo: {
        name: pull.head_ref,
        listCacheKey: ref_list_cache_key,
        canEdit: can_edit?,
        refType: "branch",
        currentOid: pull.head_sha
      },
      repo: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      copilotAccessAllowed: with_database_error_fallback(fallback: false) { copilot_chat_enabled_for_current_user? },
      findFileWorkerPath: find_file_worker_path,
      diffPaths: diff_paths,
      fileStatuses: file_statuses,
      webCommitInfo: web_commit_info,
      helpUrl: GitHub.help_url,
      copilot: {
        **copilot_chat_payload,
        ssoOrganizations: sso_organizations,
        currentTopic: repo_props(repo: current_repository, ref_name: pull.head_ref),
      },
      compareRef: params[:compare_ref],
      showOverview: params[:show_overview],
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
      number: pull.number,
      title: pull.title,
      headBranch: pull.head_ref,
      headSHA: pull.head_sha,
      baseBranch: pull.base_ref,
    }
  end

  def async_pull_body_html
    context = {
      viewer: current_user
    }

    pull.async_body_html(context: context).then do |body_html|
      body_html || GitHub::HTMLSafeString::EMPTY
    end
  end

  def labels
    pull.labels.map { |label| { name: label.name, color: label.color } }
  end

  def is_editor_path?
    path_string.present? || is_new_file_path?
  end

  def is_new_file_path?
    request&.path&.ends_with?("/edit/new")
  end

  def focused_task_data
    comment_id = params[:pull_request_review_comment_id]
    return {} unless comment_id

    comment = PullRequestReviewComment.find_by(id: comment_id, pull_request_id: pull.id)
    return {} unless comment

    thread = comment.pull_request_review_thread
    return {} if thread.nil? || thread.outdated? || thread.resolved?

    # Note can't use typical to_text, have to get intermediate raw version
    suggestion = GitHub::Goomba::PRCommentSuggestionPipeline.call(comment.body)[:raw_suggestion]

    # If the comment doesn't have a suggestion, we'll let copilot try to generate a suggestion from it
    if (suggestion.nil? || suggestion.empty?) && user_feature_enabled?(:hadron_comment_fix_generation)
      comments = thread.comments.map do |comment|
        {
          author: {
            login: comment.user.display_login,
            avatarUrl: comment.user.primary_avatar_url(24),
          },
          body: comment.body_html,
          createdAt: comment.created_at,
        }
      end

      return {
        focusedTask: {
          comments:,
          html: "",
          sourceId: comment_id.to_i,
          sourceType: "pull_request_review_comment",
          suggestions: [],
          type: "generative"
        }
      }
    end

    # Single line just has line, multi has both, normalize the start
    start_line = (thread.start_line_number || thread.line)
    end_line = thread.line

    # Get original content lines from the blob
    blob = current_repository.blob(pull.head_sha, thread.path, blob_limits)
    original_lines = blob.data
      .split(DiffEntrySuggestedChange::NEWLINE_REGEXP, -1)
      .slice((start_line - 1)..(end_line - 1))
      .map do |line|
        "-#{line}"
      end

    suggestion_lines = suggestion
      .split(DiffEntrySuggestedChange::NEWLINE_REGEXP, -1)
      .map do |line|
        "+#{line}"
      end

    context = { subject: comment }

    suggester_info = if comment.user
      {
        suggester: {
          displayLogin: comment.user&.display_login,
          avatarUrl: avatar_url_for(comment.user),
        }
      }
    else
      {}
    end

    {
      focusedTask: {
        sourceId: comment.id,
        sourceType: "pull_request_review_comment",
        html: GitHub::Goomba::MarkdownPipeline.to_html(comment.body, context, nil),
        suggestions: [
          {
            filePath: thread.path,
            oldStart: start_line,
            oldLines: original_lines.count,
            newStart: start_line,
            newLines: suggestion_lines.count,
            lines: original_lines + suggestion_lines,
          }
        ],
        **suggester_info
      }
    }
  end

  memoize def pull
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  memoize def async_start_oid
    pull.async_merge_base
  end

  memoize def async_pull_request_tree_data
    diff_paths = {}
    file_statuses = {}
    async_start_oid.then do |start_oid|
      end_oid = pull.head_sha
      if start_oid && end_oid
        begin
          start_commit, end_commit = pull.compare_repository.commits.find([start_oid, end_oid])
          pull_comparison = PullRequest::Comparison.new(pull: pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit, viewer: current_user)
          walk_diff_nodes(pull_comparison.diffs.to_tree.nodes, "", diff_paths, file_statuses)

          next file_statuses, diff_paths
        rescue GitRPC::ObjectMissing
        end
      end
    end
  end

  # diff_items should follow the same structure as file_tree:
  # {"dir/path" => { totalCount: 2, items: [{name: "file1", type: "file", path: "dir/path/file1"}, {name: "dir2", type: "dir", path: "dir/path/dir2"}]}}
  def walk_diff_nodes(nodes, current_path, diff_paths, file_statuses)
    diff_items = []
    diff_paths[current_path] = { totalCount: nodes.size, items: diff_items }
    nodes.each do |_key, node|
      path = "#{!current_path.empty? ? current_path + "/" : ""}#{node.name}"
      if node.nodes.present?
        diff_items << { name: node.name, contentType: :directory, path: path, hasSimplifiedPath: node.name.include?("/") }
        walk_diff_nodes(node.nodes, path, diff_paths, file_statuses)
      else
        diff_items << { name: node.name, contentType: :file, path: path }
        file_statuses[path] = node.delta.status
      end
    end
  end
end
