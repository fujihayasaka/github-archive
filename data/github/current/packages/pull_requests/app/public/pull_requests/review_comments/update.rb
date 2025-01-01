# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Update
      extend T::Sig

      module_function

      sig do
        params(
          comment: PullRequestReviewComment,
          body: String,
          user: User,
        ).returns(NilClass)
      end
      def update(comment:, body:, user:)
        comment.update_body(body, user)
      end
    end
  end
end
