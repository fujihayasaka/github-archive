# typed: true
# frozen_string_literal: true

class Discussions::ChosenCommentsController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_discussion_is_question
  before_action :require_discussion_comment
  before_action :add_spamurai_form_signals, only: [:create, :destroy]

  def create
    return render_404 unless discussion_comment.can_mark_as_answer?(current_user)

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if discussion_comment.mark_as_answer(actor: current_user)
      if request.xhr?
        discussion.reload
        render_single_comment(discussion_comment)
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      if request.xhr?
        render json: discussion_comment.errors.full_messages, status: :unprocessable_entity
      else
        flash[:error] = "Could not mark as answer at this time."
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  def destroy
    return render_404 unless discussion_comment.can_unmark_as_answer?(current_user)

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if discussion_comment.unmark_as_answer(actor: current_user)
      if request.xhr?
        discussion.reload
        render_single_comment(discussion_comment)
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      if request.xhr?
        render json: discussion_comment.errors.full_messages, status: :unprocessable_entity
      else
        flash[:error] = "Could not remove as answer at this time."
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  private

  def require_discussion_is_question
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    unless discussion.supports_mark_as_answer?
      flash[:error] = "Cannot mark or unmark an answer for a discussion that is not a question."
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
