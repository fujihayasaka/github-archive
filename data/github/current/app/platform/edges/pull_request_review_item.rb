# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class PullRequestReviewItem < Edges::Base
      required_capabilities [:mobile_only_schema_mask]

      node_type Unions::PullRequestReviewItem
    end
  end
end
