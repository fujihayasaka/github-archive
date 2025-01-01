# typed: true
# frozen_string_literal: true
class Copilot::TaskDiffController < Copilot::TaskControllerBase
  include Commit::ReactPayloadDataDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  def show
    return head :not_found unless current_user&.hadron_editor_preview_enabled?
    respond_to do |format|
      format.json do
        start_oid, end_oid = pull.merge_base, pull.head_sha
        return head :not_acceptable unless start_oid && end_oid

        _, end_commit = pull.compare_repository.commits.find([start_oid, end_oid])
        diff = GitHub::Diff.new(current_repository, start_oid, end_oid)
        file_list_view = ::Diff::FileListView.new(commit: end_commit, diffs: diff, current_user: current_user)
        payload = build_file_diff_payload(file_list_view, 0).as_json(only: ALLOWED_DIFF_JSON_FIELDS)

        render json: payload
      end
    end
  end

  private

  memoize def pull
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end
end
