# typed: true
# frozen_string_literal: true

class Discussions::CommentMinimizationsController < Discussions::BaseController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  # An upper bound on the number of comments to render directly within the HTML fragment returned by the #create
  # action. If more comments than this exist between the anchor and the newly created comment, then this many
  # of the *most recent* comments will be returned instead.
  MAXIMUM_FRAGMENT_PAGES = Discussions::CommentsController::MAXIMUM_FRAGMENT_PAGES

  # Keep our page sizes consistent with the ThreadsController for a consistent paging experience.
  NUMBER_OF_NESTED_COMMENTS_PER_PAGE = Discussions::Comments::ThreadsController::NUMBER_OF_NESTED_COMMENTS_PER_PAGE

  before_action :login_required
  before_action :require_discussion
  before_action :require_discussion_comment
  before_action :require_minimize_state_is_toggleable, only: [:create, :destroy]
  before_action :add_spamurai_form_signals, only: [:create, :destroy]

  def create
    reason = ""
    staff = false
    discussion_comment = T.must_because(self.discussion_comment) { "#require_discussion_comment ensures non-nil" }
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    # Set the actor so we can log a Hydro event about this comment
    # being updated.
    discussion_comment.actor = current_user

    # Convert the classifier reason to the correct format by using the same conversion
    # logic that the GraphQL layer uses.
    minimize_classifier = Platform::Enums::ReportedContentClassifiers.values[params[:classifier]]&.value
    return head :unprocessable_entity unless minimize_classifier.present?

    if discussion_comment.set_minimized(current_user, reason, minimize_classifier, discussion_comment.author, staff)
      if request.xhr?
        render_single_comment(discussion_comment)
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      error_message = "Could not hide the comment at this time."
      if request.xhr?
        render_single_comment(
          discussion_comment,
          error_message: error_message,
          status: :unprocessable_entity,
        )
      else
        flash[:error] = error_message
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  def destroy
    reason = ""
    staff = false
    discussion_comment = T.must_because(self.discussion_comment) { "#require_discussion_comment ensures non-nil" }
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    # Set the actor so we can log a Hydro event about this comment
    # being updated.
    discussion_comment.actor = current_user

    if discussion_comment.set_unminimized(current_user, reason, discussion_comment.author, staff)
      if request.xhr?
        render_single_comment(discussion_comment)
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      error_message = "Could not unhide the comment at this time."
      if request.xhr?
        render_single_comment(
          discussion_comment,
          error_message: error_message,
          status: :unprocessable_entity
        )
      else
        flash[:error] = error_message
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  def show
    respond_to do |format|
      format.html do
        render partial: "discussion_comments/minimize_form", locals: {
          comment: discussion_comment, timeline: discussion_timeline
        }
      end
    end
  end

  private

  sig { returns T.nilable(DiscussionComment) }
  memoize def discussion_comment
    discussion&.comments&.find_by(id: params[:id].to_i)
  end

  sig { void }
  def require_discussion_comment
    render_404 unless discussion_comment
  end

  sig { returns T.nilable(String) }
  def anchor_id
    params.fetch(:anchor_id, nil)
  end

  sig { returns Integer }
  def back_page
    params.fetch(:back_page, 0).to_i
  end

  sig { returns DiscussionTimeline::SingleCommentRenderContext }
  def discussion_timeline_render_context
    DiscussionTimeline::SingleCommentRenderContext.new(
      discussion,
      discussion_comment,
      viewer: current_user,
      cap_filter: cap_filter,
      nested_comments_per_page: NUMBER_OF_NESTED_COMMENTS_PER_PAGE,
      back_page: back_page,
      forward_page: MAXIMUM_FRAGMENT_PAGES,
      anchor_id: anchor_id,
    )
  end

  sig { void }
  def require_minimize_state_is_toggleable
    has_permission = DiscussionComment.can_toggle_minimized_discussion_comment?(
      discussion, actor: current_user
    )
    render_404 unless has_permission
  end
end
