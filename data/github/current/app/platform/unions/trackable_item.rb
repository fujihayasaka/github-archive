# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class TrackableItem < Platform::Unions::Base
      description "Types that can be tracked in a tasklist block (eg: Issues, Draft)"

      possible_types(
        Objects::TrackedDraftItem,
        Objects::TrackedIssueReference
      )

      def self.resolve_type(object, context)
        if object.is_a?(::TasklistBlocks::IssueReference)
          Objects::TrackedIssueReference
        elsif object.is_a?(::TrackingBlocks::DraftIssue)
          Objects::TrackedDraftItem
        else
          raise Errors::Internal, "Unexpected trackable item: #{object.inspect}"
        end
      end
    end
  end
end
