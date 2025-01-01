# typed: false
# frozen_string_literal: true

module DiscussionsDashboardHelper
  def discussions_dashboard_search_path
    if link_selected?(all_discussions_commented_path)
      all_discussions_commented_path
    else
      all_discussions_path
    end
  end
end
