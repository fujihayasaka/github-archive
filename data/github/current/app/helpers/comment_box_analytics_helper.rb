# typed: true
# frozen_string_literal: true

module CommentBoxAnalyticsHelper
  include AnalyticsHelper

  COMMENT_BOX_CATEGORY = "comment_box"

  def comment_box_tracking(action)
    analytics_click_attributes(
      category: COMMENT_BOX_CATEGORY,
      action: action,
    )
  end

  def safe_comment_box_tracking(action)
    safe_analytics_click_attributes(
      category: COMMENT_BOX_CATEGORY,
      action: action,
    )
  end
end
