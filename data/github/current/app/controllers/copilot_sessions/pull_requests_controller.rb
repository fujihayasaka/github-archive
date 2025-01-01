# typed: true
# frozen_string_literal: true

class CopilotSessions::PullRequestsController < ApplicationController
  include Commit::ReactPayloadDataDependency

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Configurations,

  def index
    return render_404 unless request.xhr?
    pull_request_ids = params["pull_request_ids"] || []

    pr_map = CopilotSweAgent::Public.id_to_pull_request_map(pull_request_ids:
      pull_request_ids.split(",").map(&:to_i), user: current_user)

    if params["include_diffs"] == "true"
      pr_map = add_diffs_to_pull_requests(pr_map)
    end

    render json: { pull_requests: pr_map }
  end

  private

  def target_for_conditional_access
    current_user
  end

  def add_diffs_to_pull_requests(pr_map)
    # Attaches diff data to each pull request
    pull_request_ids = pr_map.keys
    pull_requests = PullRequest.includes(:repository).where(id: pull_request_ids).index_by(&:id)

    pr_map.transform_values do |pr_data|
      pull_request = pull_requests[pr_data.id]

      if pull_request
        begin
          diff_data = compute_pull_request_diffs(pr_data.id, pull_request)
          pr_data.with(diffs: diff_data)
        rescue => e
          Rails.logger.warn("Failed to compute diffs for PR #{pr_data.id}: #{e.message}")
          Rails.logger.warn("Backtrace: #{e.backtrace&.join("\n")}")

          # Set diffs to nil if computation failed
          pr_data.with(diffs: nil)
        end
      else
        pr_data.with(diffs: nil)
      end
    end
  end

  def compute_pull_request_diffs(pr_id, pull_request)
    return nil unless pull_request&.repository

    start_oid, end_oid = pull_request.merge_base, pull_request.head_sha
    return nil unless start_oid && end_oid

    begin
      start_commit, end_commit = pull_request.compare_repository.commits.find([start_oid, end_oid])
      diff_options = {
        base_repository: pull_request.base_repository,
        head_repository: pull_request.head_repository,
      }
      diff = GitHub::Diff.new(pull_request.compare_repository, start_oid, end_oid, diff_options)
      file_list_view = ::Diff::FileListView.new(commit: end_commit, diffs: diff, current_user: current_user)

      # Get the rich diff payload with syntax highlighting
      build_file_diff_payload(file_list_view, 0, current_user).as_json(only: ALLOWED_DIFF_JSON_FIELDS)
    rescue GitRPC::Error => e
      Rails.logger.error "Failed to compute diffs for PR #{pr_id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace&.join("\n")}"
      nil
    end
  rescue => e
    Rails.logger.error "Failed to compute diffs for PR #{pr_id}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace&.join("\n")}"
    nil
  end
end
