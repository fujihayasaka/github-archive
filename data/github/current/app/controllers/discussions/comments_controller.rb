# typed: true
# frozen_string_literal: true

class Discussions::CommentsController < Discussions::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:show]

  # An upper bound on the number of comments to render directly within the HTML fragment returned by the #create
  # action. If more comments than this exist between the anchor and the newly created comment, then this many
  # of the *most recent* comments will be returned instead.
  MAXIMUM_FRAGMENT_PAGES = 4

  # Keep our page sizes consistent with the ThreadsController for a consistent paging experience.
  NUMBER_OF_NESTED_COMMENTS_PER_PAGE = Discussions::Comments::ThreadsController::NUMBER_OF_NESTED_COMMENTS_PER_PAGE

  before_action :login_required
  before_action :require_discussion
  before_action :require_discussion_comment, only: [:update, :destroy, :show]
  before_action :add_spamurai_form_signals, only: [:create, :update]

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    return render_404 unless discussion.can_comment?(current_user)

    timeline_last_modified_at = DiscussionTimeline.last_modified_at_for(discussion: discussion)

    if comment_creator.save
      mark_discussion_as_read

      if request.xhr?
        if new_comment_parent_comment.present?
          render json: {
            updateContent: {
              "##{DiscussionComment.dom_id(new_comment.parent_comment_id)} [data-child-comments]" =>
                render_to_string(
                  Discussions::ChildCommentsComponent.new(
                    parent_comment: new_comment_parent_comment,
                    timeline: discussion_timeline,
                  ),
                ),
              "#discussion-comment-count" =>
                render_to_string(
                  Discussions::CommentCountComponent.new(discussion: discussion, repository: current_repository),
                ),
            },
          }
        else
          render json: {
            updateContent: {
              "[data-timeline-updated-at='#{timeline_last_modified_at}']" => render_to_string(
                partial: "discussions/timeline",
                formats: [:html],
                locals: {
                  timeline: new_comments_timeline(timeline_last_modified_at),
                  timeline_sort: timeline_sort,
                  org_param: org_param,
                },
              ),
              "#discussion-comment-count" => render_to_string(
                Discussions::CommentCountComponent.new(discussion: discussion, repository: current_repository),
              ),
              "#partial-discussion-form-actions" => render_to_string(
                Discussions::FormActionsComponent.new(
                  timeline: new_comments_timeline(timeline_last_modified_at),
                  is_inline_comment: false,
                )
              ),
            },
          }
        end
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      if request.xhr?
        errors = comment_creator.errors.map { |error| error.message }
        render json: { errors: errors }, status: :unprocessable_entity
      else
        flash[:error] = "Could not comment on the discussion at this time."
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  def update
    return render_404 unless discussion_comment.modifiable_by?(current_user)
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if stale_model?(discussion_comment)
      return render_stale_error(model: discussion_comment,
        error: "Could not edit comment. Please try again.", path: agnostic_discussion_path(discussion, org_param: org_param))
    end

    # Set the actor so we can log a Hydro event about this comment
    # being updated.
    discussion_comment.actor = current_user

    if update_comment
      if request.xhr?
        current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
        render json: {
          "source" => discussion_comment.body,
          "body" => discussion_comment.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
          "newBodyVersion" => discussion_comment.body_version,
          "editUrl" => edits_menu_discussion_comment_path(current_repository.owner,
            current_repository, discussion, discussion_comment),
        }
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      render_discussion_comment_update_error
    end
  end

  def destroy
    return render_404 unless discussion_comment.deletable_by?(current_user)
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if discussion_comment.wipe_or_destroy(current_user)
      if request.xhr?
        head :ok
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      if request.xhr?
        render json: discussion_comment.errors.full_messages, status: :unprocessable_entity
      else
        flash[:error] = "Could not delete the discussion comment at this time."
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  def show
    respond_to do |format|
      format.html do
        render_single_comment(discussion_comment)
      end
    end
  end

  private

  sig { returns(DiscussionComment::Creator) }
  memoize def comment_creator
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    DiscussionComment::Creator.new(
      discussion: discussion,
      actor: current_user,
      body: comment_params[:body],
      parent_comment_id: comment_params[:parent_comment_id]&.to_i,
      state_reason: state_reason,
      post_as_admin: posted_as_admin?,
    )
  end

  sig { returns(T::Boolean) }
  def posted_as_admin?
    return false unless can_post_as_admin?

    return false unless comment_params.key?(:post_as_admin)

    ActiveRecord::Type::Boolean.new.cast(comment_params[:post_as_admin])
  end

  # Private: The state reason to use when comment & closing/reopening
  sig { returns(T.nilable(String)) }
  def state_reason
    # To have parity with issues, we fall back to default values if the
    # `comment_and_*` params are set, but `state_reason` is missing.
    if params[:comment_and_close] == "1"
      params[:state_reason] || Discussion::StateReasonable::StateReason::Resolved.serialize
    elsif params[:comment_and_open] == "1"
      params[:state_reason] || Discussion::StateReasonable::StateReason::Reopened.serialize
    end
  end

  def new_comment
    return unless action_name == "create"
    comment_creator.comment
  end

  memoize def new_comment_parent_comment
    new_comment&.parent_comment
  end

  def comment_params
    params.require(:comment).permit(:body, :parent_comment_id, :post_as_admin)
  end

  memoize def discussion_comment
    discussion&.comments&.find_by(id: params[:id].to_i)
  end

  def render_discussion_comment_update_error
    if request.xhr?
      return render(json: discussion_comment.errors.full_messages, status: :unprocessable_entity)
    end

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    flash[:error] = "Could not edit the discussion comment at this time."
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  def require_discussion_comment
    render_404 unless discussion_comment
  end

  def anchor_id
    params.fetch(:anchor_id, new_comment&.id)
  end

  def back_page
    params.fetch(:back_page, 0).to_i
  end

  def include_id
    new_comment&.id
  end

  def discussion_timeline_render_context
    target_comment = new_comment_parent_comment || discussion_comment
    render_context = DiscussionTimeline::SingleCommentRenderContext.new(
      discussion,
      target_comment,
      viewer: current_user,
      cap_filter: cap_filter,
      nested_comments_per_page: NUMBER_OF_NESTED_COMMENTS_PER_PAGE,
      back_page: back_page,
      forward_page: MAXIMUM_FRAGMENT_PAGES,
      anchor_id: anchor_id,
    )

    if include_id
      thread = render_context.reply_threads_by_parent_id[target_comment.id]
      if thread.replies.none? { |reply| reply.id == include_id }
        # The render context we just built doesn't include the new comment! The anchor must be too far back for the
        # new comment to fit on the next page.
        #
        # Build a new render context by anchoring to the newly created comment's ID (:include_id) and including a
        # (generous) page before.

        render_context = DiscussionTimeline::SingleCommentRenderContext.new(
          discussion,
          target_comment,
          viewer: current_user,
          cap_filter: cap_filter,
          nested_comments_per_page: NUMBER_OF_NESTED_COMMENTS_PER_PAGE,
          back_page: MAXIMUM_FRAGMENT_PAGES,
          forward_page: 0,
          anchor_id: include_id,
        )
      end
    end

    render_context
  end

  def new_comments_timeline(last_modified_at)
    render_context = DiscussionTimeline::LiveUpdatesRenderContext.new(
      discussion,
      viewer: current_user,
      timeline_last_rendered: last_modified_at,
      cap_filter: cap_filter
    )

    DiscussionTimeline.new(render_context: render_context)
  end

  def update_comment
    if operation = TaskListOperation.from(params[:task_list_operation])
      text = operation.call(discussion_comment.body)
      discussion_comment.update_body(text, current_user)
    else
      discussion_comment.update_body(comment_params[:body], current_user)
    end
  end
end
