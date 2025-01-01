# typed: true
# frozen_string_literal: true

class Copilot::Workbench::BaseEditorController < AbstractRepositoryController
  before_action :login_required
  before_action :require_feature_access

  private

  memoize def pull
    PullRequests::PullRequestAccessor.new.by_number(repository_id: current_repository.id, number: params[:id].to_i)
  rescue GH::Errors::ObjectNotFound
    nil
  end

  def require_feature_access
    unless feature_enabled_globally_or_for_current_user?(:copilot_workbench)
      render_404
    end
  end

  def blob_limits
    { truncate: false, limit: 2.megabytes }
  end

  memoize def async_start_oid
    pull.async_merge_base
  end

  # diff_items should follow the same structure as file_tree:
  # {"dir/path" => { totalCount: 2, items: [{name: "file1", type: "file", path: "dir/path/file1"}, {name: "dir2", type: "dir", path: "dir/path/dir2"}]}}
  def walk_diff_nodes(nodes, current_path, diff_paths, file_statuses, lines_changed)
    diff_items = []
    diff_paths[current_path] = { totalCount: nodes.size, items: diff_items }
    nodes.each do |_key, node|
      path = "#{ !current_path.empty? ? current_path + "/" : "" }#{ node.name }"
      if node.nodes.present?
        diff_items << { name: node.name, contentType: :directory, path: path, hasSimplifiedPath: node.name.include?("/") }
        walk_diff_nodes(node.nodes, path, diff_paths, file_statuses, lines_changed)
      else
        diff_items << { name: node.name, contentType: :file, path: path }
        file_statuses[path] = node.delta.status
        lines_changed[path] = { additions: node.delta.additions, deletions: node.delta.deletions }
      end
    end
  end

  memoize def async_pull_request_tree_data
    diff_paths = {}
    file_statuses = {}
    lines_changed = {}
    async_start_oid.then do |start_oid|
      end_oid = pull.head_sha
      if start_oid && end_oid
        begin
          start_commit, end_commit = pull.compare_repository.commits.find([start_oid, end_oid])
          pull_comparison = PullRequest::Comparison.new(pull: pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit, viewer: current_user)

          walk_diff_nodes(pull_comparison.diffs.to_tree.nodes, "", diff_paths, file_statuses, lines_changed)
          lines_changed[""] = { additions: pull_comparison.additions, deletions: pull_comparison.deletions }
          next file_statuses, diff_paths, lines_changed
        rescue GitRPC::ObjectMissing
        end
      end
    end
  end
end
