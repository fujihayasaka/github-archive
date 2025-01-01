# typed: true
# frozen_string_literal: true

class Discussions::ActionsMenusController < Discussions::BaseController
  before_action :require_discussion
  before_action :require_readable_target

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    if request.xhr?
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      render Discussions::CommentActionsMenuComponent.new(
        timeline: discussion_timeline,
        discussion_or_comment: target,
        form_path: form_path,
        is_comment_minimized: target.try(:minimized?),
        current_repository: current_repository,
        org_param: org_param,
      ), layout: false
    else
      render_404
    end
  end

  private

  def discussion_timeline_render_context
    if target.is_a?(DiscussionComment)
      DiscussionTimeline::SingleCommentRenderContext.new(
        discussion,
        discussion_comment,
        viewer: current_user,
        cap_filter: cap_filter
      )
    else
      DiscussionTimeline::DiscussionBodyRenderContext.new(
        discussion,
        viewer: current_user,
        cap_filter: cap_filter
      )
    end
  end

  def discussion_comment
    discussion&.comments&.find(params[:comment_id])
  end

  def form_path
    params[:form_path]
  end

  def require_readable_target
    render_404 unless target&.readable_by?(current_user)
  end

  def target
    if params[:target] == "discussion_comment"
      discussion_comment
    else
      discussion
    end
  end
end
