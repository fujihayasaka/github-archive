# typed: true
# frozen_string_literal: true

class Discussions::VerifiedAnswersController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_discussion_supports_verified_answers
  before_action :require_discussion_comment
  before_action :add_spamurai_form_signals
  before_action :require_verified_answer_support

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if discussion_comment.mark_as_verified_answer(actor: current_user)
      respond_with_verified_answer_success(discussion)
    else
      respond_with_verified_answer_failure(discussion, error: "Could not verify an answer at this time.")
    end
  end

  def destroy
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if discussion_comment.unmark_as_verified_answer(actor: current_user)
      respond_with_verified_answer_success(discussion)
    else
      respond_with_verified_answer_failure(discussion, error: "Could not unverify an answer at this time.")
    end
  end

  private

  def require_verified_answer_support
    render_404 unless discussion_comment.supports_verified_answers?(current_user)
  end

  def respond_with_verified_answer_failure(discussion, error:)
    if request.xhr?
      render json: discussion_comment.errors.full_messages, status: :unprocessable_entity
    else
      flash[:error] = error
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  def respond_with_verified_answer_success(discussion)
    if request.xhr?
      render_single_comment(discussion_comment)
    else
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  def require_discussion_supports_verified_answers
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    unless discussion.supports_mark_as_answer?
      flash[:error] = "You can only mark or unmark an answer as verified for discussions that are questions."
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  memoize def discussion_comment
    discussion&.comments&.find_by(id: params[:id].to_i)
  end

  def require_discussion_comment
    render_404 unless discussion_comment
  end
end
