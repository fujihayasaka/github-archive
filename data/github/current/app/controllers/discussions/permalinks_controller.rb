# typed: true
# frozen_string_literal: true

class Discussions::PermalinksController < Discussions::BaseController
  before_action :require_discussion
  before_action :require_valid_anchor

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    render Discussions::CollapsibleTimelineComponent.new(timeline: discussion_timeline, org_param: org_param), layout: false
  end

  private

  memoize def anchor_id
    params[:anchor]&.match(/\A#{DiscussionComment::DOM_ID_PREFIX}([0-9]+)\z/i)&.captures&.first&.to_i
  end

  memoize def anchor_comment
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    discussion.
      comments.
      filter_spam_for(current_user).
      find_by(id: anchor_id)
  end

  def permalink_comment
    anchor_comment&.parent_comment || anchor_comment
  end

  def discussion_timeline_render_context
    render_context = DiscussionTimeline::PermalinkRenderContext.new(
      discussion,
      viewer: current_user,
      cap_filter: cap_filter,
      before_cursor: params[:before],
      after_cursor: params[:after],
      permalink_comment: permalink_comment,
      anchor_id: anchor_id,
    )
    unless render_context.item_between_cursors?(permalink_comment)
      render_context = DiscussionTimeline::SingleCommentRenderContext.new(
        discussion,
        permalink_comment,
        viewer: current_user,
        cap_filter: cap_filter
      )
    end
    render_context
  end

  def require_valid_anchor
    head 404 unless anchor_id.present? && anchor_comment.present?
  end
end
