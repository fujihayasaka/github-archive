# typed: true
# frozen_string_literal: true

class Gists::CommentsController < Gists::ApplicationController
  include ShowPartial

  before_action :gist_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:comment_actions_menu]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:edit_form]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def create
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    comment_body = params[:comment][:body]
    comment = this_gist.comments.build(body: comment_body, user: current_user)

    # Don't allow blocked users to comment on gists
    if comment.author_blocking?(current_user)
      valid = false
      comment.errors.add(:message, "cannot be saved")
    elsif valid = comment.save
      flash[:ga_gist_comment] = true # Track GA event on next page load

      GitHub.dogstats.increment("gist.web.comment", \
                                tags: ["visibility:#{this_gist.visibility}",
                                       "ownership:#{this_gist.ownership}"])
    end

    respond_to do |format|
      format.html do
        if valid
          redirect_to user_gist_path(this_gist.user_param, this_gist, anchor: comment.anchor)
        else
          flash[:error] = comment.errors.full_messages.to_sentence
          redirect_to :back
        end
      end

      format.json do
        if valid
          render_update_content_json({
            timeline_marker: render_to_string(
              partial: "gists/gists/timeline_marker",
              object: this_gist,
              formats: :html,
            ),
            form_actions: render_to_string(
              partial: "gists/gists/form_actions",
              object: this_gist,
              formats: :html,
            ),
          })
        else
          errors = comment.errors.map(&:message)
          render json: { errors: errors }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    comment = this_comment
    comment_body = params.fetch(:gist_comment, {}).fetch(:body, nil)
    valid = false

    if comment.author_blocking?(current_user)
      valid = false
      comment.errors.add(:message, "cannot be saved")
    elsif this_comment.adminable_by?(current_user) && comment_body.present?
      if operation = TaskListOperation.from(params[:task_list_operation])
        text = operation.call(comment.body)
        comment.update_body(text, current_user) if text
        valid = true
      else
        valid = comment.update_body(comment_body, current_user)
      end
    end

    respond_to do |wants|
      wants.html do
        redirect_to user_gist_path(this_gist.user_param, this_gist)
      end

      wants.json do
        if valid
          render json: {
            "source" => comment.body,
            "body" => comment.body_html,
            "newBodyVersion" => comment.body_version,
            "editUrl" => show_comment_edit_history_path(comment.global_relay_id),
          }
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def comment_actions_menu # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?
    return render_404 unless this_comment

    render partial: "gists/gists/comment_actions_menu", locals: {
      comment: this_comment
    }
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    comment = this_comment
    if comment.adminable_by?(current_user)

      render Comments::EditForm::EditFormComponent.new(
        comment: comment,
        comment_context: params[:comment_context],
        textarea_id: params[:textarea_id]
      ), layout: false
    else
      head :forbidden
    end
  end

  def destroy
    if this_comment.adminable_by?(current_user)
      this_comment.destroy
    end

    if request.xhr?
      head :ok
    else
      redirect_to user_gist_path(this_gist.user_param, this_gist)
    end
  end

  def show
    if this_comment
      render Gists::CommentComponent.new(comment: this_comment, gist: this_gist, render_minimized: true), formats: [:html], layout: false
    else
      render_404
    end
  end

  private

  # Enterprise Managed Users are not allowed to create Gists
  # Only write operations will reach this stage
  def emu_ownership_satisfied(resource:, target_provider:)
    :no
  end

  # A simple before filter to ensure the gist could be found.
  def gist_required
    this_gist!
  end

  def this_comment # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @comment ||= this_gist.comments.find(params[:comment_id])
  end
end
