# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PullRequestReviewThread < Connections::Base
      description "Review comment threads for a pull request review."
      total_count_field

      field :filtered_count, Integer, visibility: :internal, description: "Identifies the count of items after applying `before` and `after` filters.", null: false

      field :page_count, Integer, visibility: :internal, description: "Identifies the count of items after applying `before`/`after` filters and `first`/`last`/`skip` slicing.", null: false

      field :total_comments_count, Integer, visibility: :internal, description: "The total number of underlying comments within these threads", null: false

      def total_comments_count
        pull = @object.parent
        thread_ids = @object.items.map(&:id)

        pull.review_comments.in_viewable_state_for(@context[:viewer]).
          where(pull_request_review_thread_id: thread_ids).
          count
      end
    end
  end
end
