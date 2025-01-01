# typed: true
# frozen_string_literal: true

# Public: Handles rendering a dropdown menu that contains a list of the revisions for
# a Discussion or a DiscussionComment.
class Discussions::EditsController < Discussions::BaseController
  before_action :require_discussion
  before_action :require_discussion_comment_if_necessary
  before_action :require_edit_history_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:edit_history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:edit_history_log]

  def edit_history_log # rubocop:todo GitHub/UseRestfulActions
    render Discussions::EditHistory::ListComponent.new(
      editable: discussion_or_comment,
    ), layout: false
  end

  def edit_history # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Discussions::EditHistoryComponent.new(
          discussion_or_comment: discussion_or_comment,
          timeline: discussion_timeline,
        ), layout: false
      end
    end
  end

  private

  memoize def discussion_comment
    discussion&.comments&.find_by(id: params[:id].to_i) if params[:id]
  end

  def discussion_or_comment
    discussion_comment || discussion
  end

  def discussion_timeline_render_context
    DiscussionTimeline::SingleCommentRenderContext.new(
      discussion,
      discussion_comment,
      viewer: current_user,
      cap_filter: cap_filter
    )
  end

  def require_discussion_comment_if_necessary
    return unless params[:id] && params[:discussion_number]
    render_404 unless discussion_comment
  end

  def require_edit_history_access
    render_404 unless discussion_or_comment.viewer_can_read_user_content_edits?(current_user)
  end
end
