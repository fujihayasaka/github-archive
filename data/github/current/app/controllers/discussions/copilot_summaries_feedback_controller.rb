# typed: true
# frozen_string_literal: true

class Discussions::CopilotSummariesFeedbackController < Discussions::BaseController
  extend T::Sig
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :require_feature
  before_action :login_required
  before_action :require_copilot_enterprise
  before_action :require_discussion
  before_action :parse_json_params

  def create
    feedback_choices = params[:feedback_choices] || []
    success = summarizer.instrument_copilot_summary_feedback(
      actor: current_user,
      feedback_choices: feedback_choices,
      feedback_text: feedback_text,
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

  def require_feature
    super # check that discussions is enabled
    return if performed? # bail out if we've already rendered a response

    render_404 unless current_user&.copilot_discussion_summary_feature_enabled?
  end

  def require_copilot_enterprise
    render_404 unless current_copilot_user&.has_copilot_enterprise_access?
  end

  sig { returns Discussion::CopilotSummarizer }
  def summarizer
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    Discussion::CopilotSummarizer.new(discussion: discussion)
  end

  sig { returns T.nilable(T::Boolean) }
  def user_feedback_opt_in_enabled?
    org = this_organization
    if org
      Copilot::Organization.new(org).user_feedback_opt_in_enabled?
    else
      current_copilot_user&.user_feedback_opt_in_enabled?
    end
  end

  def feedback_text
    params[:feedback_text].presence if user_feedback_opt_in_enabled?
  end
end
