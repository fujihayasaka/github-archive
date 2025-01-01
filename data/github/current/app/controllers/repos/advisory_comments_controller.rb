# typed: true
# frozen_string_literal: true

class Repos::AdvisoryCommentsController < Repos::AdvisoryBaseController
  include CommentsHelper

  before_action :login_required
  before_action :advisory
  before_action :disallow_for_blocked_users, only: [:create, :update]
  before_action :authorize_advisory_writable
  before_action :authorize_advisory_state_change, only: [:create],
    if: :state_change_requested?

  def create
    comment = nil # For variable scoping

    if params[:comment_and_close].present?
      comment = advisory.comment_and_close(current_user, params[:body])
    elsif params[:comment_and_reopen].present?
      comment = advisory.comment_and_reopen(current_user, params[:body])
    else
      comment = advisory.create_comment(current_user, params[:body])
    end

    if comment && comment.persisted?
      # Comment creation succeeded
      redirect_to comment.permalink
    elsif comment
      # Comment creation failed
      flash[:error] = comment.errors.full_messages.to_sentence
      redirect_to :back
    else
      # Comment creation was not requested
      redirect_to :back
    end
  end

  def update
    comment = advisory.comments.find_by!(id: params[:comment_id])

    return render_404 unless comment.viewer_can_update?(current_user)

    text =
      if operation = TaskListOperation.from(params[:task_list_operation])
        operation.call(comment.body)
      else
        params[:repository_advisory_comment][:body]
      end

    comment.update_body(text, current_user) if text

    respond_to do |wants|
      wants.html do
        redirect_to :back
      end
      wants.json do
        if comment.valid?
          render json: {
            source: comment.body,
            body: comment.body_html,
            newBodyVersion: comment.body_version,
            editUrl: show_comment_edit_history_path(comment.global_relay_id),
          }
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    comment = advisory.comments.find_by!(id: params[:comment_id])
    return render_404 unless comment.viewer_can_delete?(current_user)

    comment.destroy

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def authorize_advisory_state_change
    render_404 unless advisory.adminable_by?(current_user) || (authorized_pvd_author? && advisory.open?)
  end

  # Is this user the author of a PVD submission and is PVD workflow enabled here?
  # We already know they can access the advisory based on `#authorize_advisory_writable`
  memoize def authorized_pvd_author?
    advisory.external? &&
      advisory.author == current_user &&
      helpers.use_pvd_workflow?
  end

  def disallow_for_blocked_users
    if blocked_from_commenting?(advisory)
      flash[:error] = "You can't perform that action at this time."
      redirect_to advisory.permalink
    end
  end

  def state_change_requested?
    params[:comment_and_close].present? || params[:comment_and_reopen].present?
  end
end
