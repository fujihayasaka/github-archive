# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Create
      module Enums
        class ReviewSubmitAction < T::Enum
          enums do
            Comment = new(:comment)
            Approve = new(:approve)
            RequestChanges = new(:request_changes)
            CreatePendingComment = new(:create_pending_comment)
          end

          sig do
            params(
              value: T.any(String, Symbol, ReviewSubmitAction, NilClass),
              default: ReviewSubmitAction
            ).returns(ReviewSubmitAction)
          end
          def self.deserialize_with_default(value, default:)
            return value if value&.is_a?(ReviewSubmitAction)
            # Normalize input to lowercase symbol for comparison
            value = value&.to_s&.strip&.downcase&.to_sym
            case value
            when :comment then Comment
            when :approve then Approve
            when :request_changes then RequestChanges
            when :create_pending_comment then CreatePendingComment
            else default
            end
          end
        end
      end
    end
  end
end
