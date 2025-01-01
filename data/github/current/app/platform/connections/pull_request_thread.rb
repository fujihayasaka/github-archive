# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PullRequestThread < Connections::Base
      description "Comment threads for a pull request."
      total_count_field

      field :total_comments_count, Integer, visibility: :internal, description: "The total number of underlying comments within these threads", null: false

      def total_comments_count
        pull = if @object.parent.class.name == "PullRequest"
          # handle thread connection that is a field of the pull request
          @object.parent
        elsif @object.parent.respond_to?(:pull_request)
          # handle thread connection that is a field on a diff entry
          @object.parent.pull_request
        elsif @object.parent[:pull_request]
          # handle thread connection that is a field on a diff entry's diff line
          @object.parent[:pull_request]
        end

        return 0 unless pull

        thread_ids = @object.items.map { |pr_thread| pr_thread.review_thread.id }

        pull.review_comments.in_viewable_state_for(@context[:viewer]).
          where(pull_request_review_thread_id: thread_ids).
          count
      end
    end
  end
end
