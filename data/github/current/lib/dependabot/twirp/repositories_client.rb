# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class RepositoriesClient < Dependabot::Twirp::BaseClient
      def unpause(repository_id:, reason:)
        rpc(:Unpause, repository_github_id: repository_id, reason: reason)
      end

      private

      def twirp_class
        DependabotApi::V1::RepositoriesClient
      end
    end
  end
end
