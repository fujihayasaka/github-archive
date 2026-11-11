# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class RepositoryAccessServiceClient < Dependabot::Twirp::BaseClient
      def get_repository_access(owner_github_id:)
        rpc(:GetRepositoryAccess, owner_github_id: owner_github_id)
      end

      def set_selected_repositories(owner_github_id:, repository_github_ids:)
        rpc(
          :SetSelectedRepositories,
          owner_github_id: owner_github_id,
          repository_github_ids: repository_github_ids,
        )
      end

      private

      def twirp_class
        DependabotApi::V1::RepositoryAccessServiceClient
      end
    end
  end
end
