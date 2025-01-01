# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueOrderField < Platform::Enums::Base
      description "Properties by which issue connections can be ordered."

      value "CREATED_AT", "Order issues by creation time", value: "created_at"
      value "UPDATED_AT", "Order issues by update time", value: "updated_at"
      value "COMMENTS", "Order issues by comment count", value: "issue_comments_count"
    end
  end
end
