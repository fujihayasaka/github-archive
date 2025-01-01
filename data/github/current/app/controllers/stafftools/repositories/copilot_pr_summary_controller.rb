# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::CopilotPrSummaryController < StafftoolsController
  before_action :dotcom_required # not available in enterprise
  before_action :ensure_repo_exists
  before_action :copilot_for_prs_enabled

  rescue_from JobStatus::NotFound, with: :render_404

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    failed_prs_count = 0
    successful_prs_count = 0
    job_statuses = []
    failed_pr_details = []

    # the job status id for the initial job is passed via URL params when redirecting from the `create` method
    if params[:job_status_id]
      first_job_status = ::Copilot::CompletionJobStatus.find!(params[:job_status_id])
      job_statuses << first_job_status
      successful_prs_count += first_job_status.context[:pull_requests_completed]&.size || 0

      if first_job_status.context[:pull_requests_failed]
        failed_prs_count += first_job_status.context[:pull_requests_failed].size
        failed_pr_details << first_job_status.context[:pull_requests_failed]
      end

      # if subsequent summary jobs were enqueued, iterate through all of them and get the job statuses
      next_job_status_id = first_job_status.context[:next_job_status_id]
      while next_job_status_id
        next_job_status = ::Copilot::CompletionJobStatus.find!(next_job_status_id)
        job_statuses << next_job_status
        successful_prs_count += next_job_status.context[:pull_requests_completed]&.size || 0

        if next_job_status.context[:pull_requests_failed]
          failed_prs_count += next_job_status.context[:pull_requests_failed].size
          failed_pr_details << next_job_status.context[:pull_requests_failed]
        end

        next_job_status_id = next_job_status.context[:next_job_status_id]
      end
    end

    failed_pr_details.flatten!

    respond_to do |format|
      format.html do
        render(
          "stafftools/repositories/copilot_pr_summary/index",
          locals: {
            job_statuses:,
            total_prs_to_summarize: all_open_pull_requests.count,
            total_failed_prs: failed_prs_count,
            total_successful_prs: successful_prs_count,
            failed_pr_details:
          }
        )
      end
      format.json do
        return render_404 unless job_statuses.any?
        send_data(
          job_statuses.flat_map do |job_status|
            job_status.context[:pull_requests_completed]&.map do |pr_summary_data|
              all_prompts_and_completions = pr_summary_data[:all_prompts_and_completions] || []

              # map each prompt and completion to it's own turn in the conversation
              conversation = all_prompts_and_completions.flat_map.with_index do |conversation_turn_pair, index|
                [
                  { turn_number: index, actor: "Human", response: conversation_turn_pair[:prompt] },
                  { turn_number: index + 1, actor: "System", response: conversation_turn_pair[:completion] }
                ]
              end
              {
                conversation_id: pr_summary_data[:title],
                harm_category: pr_summary_data[:labels].join(" "),
                conversation:
              }
            end
          end.to_json,
          type: :json,
          disposition: "attachment",
          filename: "#{current_repository.name}-copilot-pull-request-summaries-#{first_job_status.id.sub("copilot-completion:", "")}.json"
        )
      end
    end
  end

  def create
    pull_request_ids_to_summarize = all_open_pull_requests.pluck(:id)
    job_status = PullRequests::Copilot::BulkGenerateDiffSummaryJob.enqueue(**{
      repository: current_repository,
      actor: current_user,
      pull_request_ids: pull_request_ids_to_summarize,
      pull_requests_per_job: params[:pull_requests_per_job].presence && params[:pull_requests_per_job].to_i,
    }.compact)
    redirect_to "/stafftools/repositories/#{params[:user_id]}/#{params[:id]}/copilot_pr_summary?job_status_id=#{job_status&.id}"
  end

  private

  def copilot_for_prs_enabled
    render_404 unless PullRequests::Copilot.copilot_for_prs_enabled?(current_copilot_user_v2)
  end

  def all_open_pull_requests
    current_repository.pull_requests.open_pulls
  end
end
