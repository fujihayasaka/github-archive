# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFeedbackController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :code_review_access_required

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    organization = Organization.find_by(login: params[:user_id])
    head :bad_request if organization.nil?

    pull_request_id = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request)&.id
    head :bad_request if pull_request_id.nil?

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: organization&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      comment_id: params[:comment_id],
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: params[:feedback],
      feedback_choice: params[:feedback_choice],
      text_response: params[:text_response],
    )

    if current_repository.feature_enabled_for_repo_or_owner?(:copilot_coding_guidelines) || current_user.feature_enabled?(:copilot_coding_guidelines)
      code_review_comment = \
        PullRequests::Copilot::CodeReviewComment.where.not(
          copilot_coding_guideline_id: nil
        ).find_by(
          subject_type: "PullRequestReviewComment",
          subject_id: params[:comment_id]
        )

      if code_review_comment
        feedback = PullRequests::Copilot::CodeReviewCommentFeedback.build(
          repository: current_repository,
          code_review_comment: code_review_comment,
          feedback_author_id: current_user.id,
          feedback_type: params[:feedback].downcase,
          text_response: params[:text_response],
        )
        params[:feedback_choice]&.each do |choice|
          feedback.feedback_choices.build(repository: current_repository, choice: choice.downcase)
        end

        begin
          feedback.save!
        rescue ActiveRecord::RecordInvalid
          return head :bad_request
        end
      end
    end

    head :created
  end

  private

  sig { void }
  def code_review_access_required
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    render_404 unless access.can_create_review_request?
  end
end
