# typed: true
# frozen_string_literal: true

class Copilot::RepositoryCompletionFeedbackController < AbstractRepositoryController
  include GitHub::RateLimitedRequest

  before_action :login_required
  before_action :require_feature_enabled

  rate_limit_requests only: [:update], if: :logged_in?, max: 10, ttl: 1.minute, key: :update_rate_limit_key

  def update
    job_id = params.require(:job_id)
    feedback = Copilot::CompletionFeedback.for_job(job_id)

    payload = params.require(:feedback).permit(:sentiment, :body, :contact, :classification)

    raise NotFound unless feedback.user == current_user

    respond_to do |wants|
      wants.json do
        # if the user feedback is just a :sentiment, don't store the PR summary in the database for privacy reasons
        if payload[:body].blank?
          feedback.context.delete(:completion)
        elsif job_id && job = Copilot::CompletionJobStatus.find(job_id)
          # if the user is providing detailed feedback and the job is still around, save the PR summary with the user feedback
          feedback.context = job.context
        end

        if feedback.update(payload)
          if payload[:sentiment].present?
            tags = %W[sentiment:#{feedback.sentiment}]

            GitHub.dogstats.increment("copilot.completion.feedback", tags:)
          end

          head :ok
        else
          head :bad_request
        end
      end
    end
  end

  private

  def require_feature_enabled
    render_404 unless PullRequests::Copilot.copilot_for_prs_enabled?(current_copilot_user_v2)
  end

  def update_rate_limit_key
    "copilot:repository-completion-feedback:update:#{current_user.id}"
  end
end
