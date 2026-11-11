# typed: true
# frozen_string_literal: true

require "diff-analysis"

class WorkspaceEditor::DiffController < WorkspaceEditor::ControllerBase
  include Commit::ReactPayloadDataDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    return head :not_found unless current_user&.workspace_editor_preview_enabled?(repository: current_repository)
    respond_to do |format|
      format.json do
        return head :not_acceptable unless pull.merge_base && pull.head_sha
        start_oid, end_oid = pull.merge_base, pull.head_sha

        if start_oid && end_oid
          start_commit, end_commit = pull.compare_repository.commits.find([start_oid, end_oid])
          diff_options = {
            base_repository: pull.base_repository,
            head_repository: pull.head_repository,
          }
          diff = GitHub::Diff.new(current_repository, pull.merge_base, pull.head_sha, diff_options)
          file_list_view = ::Diff::FileListView.new(commit: end_commit, diffs: diff, current_user: current_user)
          diffs = build_file_diff_payload(file_list_view, 0).as_json(only: ALLOWED_DIFF_JSON_FIELDS)

          if params[:analyze_diffs]
            categorized_diffs = analyze_diff

            return head :service_unavailable unless categorized_diffs

            diffs_by_path = diffs.index_by { |diff| diff["path"] }

            payload = categorized_diffs.each_with_object({}) do |categorized_diff, result|
              path = categorized_diff[:path]
              category = categorized_diff[:category]
              full_diff = diffs_by_path[path]
              full_diff["risk"] = categorized_diff[:diff_hunks]&.map { |hunk| hunk[:risk] }&.max
              category_list = result[category]
              if !category_list
                category_list = []
                result[category] = category_list
              end

              category_list.push(full_diff)
            end
          else
            payload = diffs
          end

          render json: payload
        end
      end
    end
  end

  private

  def analyze_diff
    diff_analysis = ::WorkspaceEditor::DiffAnalysisClient.analyze(
      pull: pull, current_user: current_user, categorize: true, detect_patch_risk: params[:detect_risk] == "true"
    )

    return nil unless diff_analysis && diff_analysis[:diff_metadata].present?

    diff_analysis[:diff_metadata]
  end

  def build_file_diff_payload(file_list_view, start_index, short_path = nil)
    file_views, new_tree_entries, old_tree_entries, highlighted_diff = get_prefilled_tree_entries(file_list_view)

    file_views.map do |diff|
      current_diff_entry = diff.diff

      shd = highlighted_diff.colorized_lines(current_diff_entry)
      if shd
        shd.each(&:freeze)
        shd.freeze
      end

      new_tree_entry_temp = new_tree_entries.find { |entry| entry.path == current_diff_entry.b_path }
      old_tree_entry_temp = old_tree_entries.find { |entry| entry.path == current_diff_entry.a_path }

      diff_lines = build_diff_line_data(current_diff_entry, shd)

      {
        diffLines: diff_lines,
        isBinary: current_diff_entry.binary?,
        isTooBig: current_diff_entry.too_big?,
        linesChanged: current_diff_entry.changes,
        newTreeEntry: if new_tree_entry_temp.nil?
                        nil
                      else
                        {
                          mode: new_tree_entry_temp.mode.to_i,
                          path: new_tree_entry_temp.path,
                          lineCount: new_tree_entry_temp.line_count,
                          isGenerated: diff.generated?,
                        }
                      end,
        oldTreeEntry: if old_tree_entry_temp.nil?
                        nil
                      else
                        {
                          mode: old_tree_entry_temp.mode.to_i,
                          path: old_tree_entry_temp.path,
                          lineCount: old_tree_entry_temp.line_count,
                        }
                      end,
        linesAdded: current_diff_entry.additions,
        linesDeleted: current_diff_entry.deletions,
        path: current_diff_entry.path,
        status: current_diff_entry.status_label.upcase,
        truncatedReason: current_diff_entry.truncated_reason,
      }
    end
  end
end
