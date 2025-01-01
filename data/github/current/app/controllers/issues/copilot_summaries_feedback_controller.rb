# typed: true
# frozen_string_literal: true

class Issues::CopilotSummariesFeedbackController < AbstractRepositoryController

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ControllerMethods::Issues

  allow_verified_fetch only: [:create]

  before_action :require_feature
  before_action :login_required
  before_action :require_copilot_access
  before_action :issue_required
  before_action :require_issues_enabled
  before_action :parse_json_params

  def create
    feedback_choices = params[:feedback_choices] || []
    success = summarizer.instrument_copilot_summary_feedback(
      feedback_choices: feedback_choices,
      feedback_text: params[:feedback_text],
      header_request_id: params[:header_request_id])
    respond_to do |format|
      format.json do
        if success
          head :created
        else
          render json: { error: "Could not submit feedback", feedback_choices: feedback_choices },
            status: :unprocessable_entity
        end
      end
    end
  end

  private

  sig { returns Issue::CopilotSummarizer }
  def summarizer
    Issue::CopilotSummarizer.new(issue: current_issue, actor: current_user)
  end

  def require_feature
    render_404 unless Issue::CopilotSummarizer.feature_enabled?(viewer: current_user)
  end

  def require_issues_enabled
    unless current_issue.pull_request?
      render_404 unless current_repository.has_issues?
    end
  end

  def require_copilot_access
    has_access = CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: current_user,
      copilot_user: current_copilot_user_v2)
    render_404 unless has_access
  end
end
