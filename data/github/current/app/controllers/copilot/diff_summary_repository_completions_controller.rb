# typed: true
# frozen_string_literal: true

class Copilot::DiffSummaryRepositoryCompletionsController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :login_required
  before_action :require_feature_enabled

  rate_limit_requests only: [:create], if: :logged_in?, max: 5, ttl: 1.minute, key: :diff_summary_rate_limit_key

  sig { void }
  def create
    respond_to do |wants|
      wants.json do
        decrypted_token = helpers.copilot_mint_token(user_session, entry_point: :copilot_diff_summary_repository_completions_controller_create).decode_and_decrypt
        base_revision, head_revision, head_repo_id, custom_prompt = params.values_at(:base_revision, :head_revision, :head_repo_id, :custom_prompt)
        job_status = PullRequests::Copilot::GenerateDiffSummaryJob.enqueue(
          repository: current_repository,
          actor: T.must(current_user),
          base_revision:,
          head_revision:,
          head_repo_id:,
          token: decrypted_token.value,
          custom_prompt:
        )

        return head(:unprocessable_entity) unless job_status

        feedback_url = repo_completion_feedback_url(current_repository.owner, current_repository, job_status.id)
        render json: {
          job: {
            url: job_status_url(job_status.id),
            feedback_url: feedback_url,
            feedback_auth_token: authenticity_token_for(feedback_url, method: :put)
          }
        }
      end
    end
  end

  private

  sig { void }
  def require_feature_enabled
    render_404 unless PullRequests::Copilot.copilot_for_prs_enabled?(current_copilot_user_v2)
  end

  sig { returns String }
  def diff_summary_rate_limit_key
    "copilot:repository-completions:diff-summary:#{T.must(current_user).id}"
  end
end
