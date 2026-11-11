# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class StarredReposView < ReposView

      def paginate?
        true
      end

      def no_repos_message
        "This user has not starred any repositories."
      end

      private

      def repos_of_interest
        user.starred_repositories.order(:name)
      end

    end
  end
end
