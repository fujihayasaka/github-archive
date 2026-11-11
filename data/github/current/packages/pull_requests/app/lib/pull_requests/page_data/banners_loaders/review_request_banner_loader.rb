# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class ReviewRequestBannerLoader
      sig do
        params(current_user: T.nilable(User), pull_request: PullRequest).returns(T::Hash[Symbol, T.untyped])
      end
      def self.build(current_user:, pull_request:)
        return { render: false } unless current_user
        return { render: false } unless pull_request.open?
        return { render: false } unless pull_request.review_requested_for?(current_user)
        return { render: false } if pull_request.user_has_violated_push_rule?(current_user)

        user_requesting = pull_request.user_requesting(current_user)

        return { render: false } unless user_requesting

        {
          render: true,
          requestedBySelf: user_requesting == current_user,
          requestingUserDisplayLogin: user_requesting.display_login,
        }
      end
    end
  end
end
