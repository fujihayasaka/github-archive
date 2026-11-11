# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewThreadOrderField < Platform::Enums::Base
      description "Properties by which pull request review thread connections can be ordered."

      value "DIFF_POSITION", "Order threads by diff position", value: "diff_position"
      value "CREATED_AT", "Order threads by creation time", value: "created_at"
    end
  end
end
