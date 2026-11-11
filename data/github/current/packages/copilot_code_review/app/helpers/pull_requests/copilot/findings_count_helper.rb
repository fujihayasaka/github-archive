# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module FindingsCountHelper
      sig do
        params(
          pull_request: PullRequest,
          user: T.nilable(User),
          user_session: T.nilable(UserSession),
          remote_ip: T.nilable(String),
        ).returns(Integer)
      end
      def self.count(pull_request, user:, user_session:, remote_ip:)
        PullRequests::Copilot::FindingsCountCache.count_for(
          pull_request,
          user: user,
          user_session: user_session,
          remote_ip: remote_ip,
        )
      end
    end
  end
end
