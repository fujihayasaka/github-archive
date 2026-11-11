# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  module Queries
    ASSIGNED_QUERY = "is:issue state:open archived:false assignee:@me sort:updated-desc"
    CREATED_QUERY = "is:issue state:open archived:false author:@me sort:updated-desc"
    MENTIONED_QUERY = "is:issue state:open archived:false mentions:@me sort:updated-desc"
    RECENT_QUERY = "is:issue involves:@me updated:>@today-1w sort:updated-desc"
  end
end
