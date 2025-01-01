# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class AnonymousGitAccessReposView < ReposView
      def no_repos_message
        "This user has no repositories with anonymous Git access enabled."
      end

      private

      def repos_of_interest
        user.anonymous_access_repositories.order(:name)
      end
    end
  end
end
