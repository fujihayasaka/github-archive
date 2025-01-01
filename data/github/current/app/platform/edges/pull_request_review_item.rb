# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class PullRequestReviewItem < Edges::Base
      mobile_only true

      node_type Unions::PullRequestReviewItem
    end
  end
end
