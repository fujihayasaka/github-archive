# typed: true
# frozen_string_literal: true

class Discussions::CommentHeaderReactionButtonsController < Discussions::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    only: [:show],
    optional: true

  # An upper bound on the number of comments to render directly within the HTML fragment returned by the #create
  # action. If more comments than this exist between the anchor and the newly created comment, then this many
  # of the *most recent* comments will be returned instead.
  MAXIMUM_FRAGMENT_PAGES = Discussions::CommentsController::MAXIMUM_FRAGMENT_PAGES

  # Keep our page sizes consistent with the ThreadsController for a consistent paging experience.
  NUMBER_OF_NESTED_COMMENTS_PER_PAGE = Discussions::Comments::ThreadsController::NUMBER_OF_NESTED_COMMENTS_PER_PAGE

  before_action :login_required
  before_action :require_discussion
  before_action :require_discussion_comment

  def show
    respond_to do |format|
      format.html do
        render Discussions::HeaderReactionButtonComponent.new(
          discussion_or_comment: discussion_comment,
          timeline: discussion_timeline,
        ), layout: false
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
end
