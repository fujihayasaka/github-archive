# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Votable
      include Platform::Interfaces::Base
      description "A subject that may be upvoted."

      field :upvote_count, Integer, null: false, method: :total_upvotes,
        description: "Number of upvotes that this subject has received."

      field :viewer_can_upvote, Boolean, null: false,
        description: "Whether or not the current user can add or remove an upvote on this subject."

      def viewer_can_upvote
        @object.async_upvotable_by?(@context[:viewer])
      end

      field :viewer_has_upvoted, Boolean, null: false,
        description: "Whether or not the current user has already upvoted this subject."

      def viewer_has_upvoted
        @object.async_has_upvoted?(@context[:viewer]).then { |result| !!result }
      end
    end
  end
end
