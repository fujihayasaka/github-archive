# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class PrivateForksView < ReposView

      def no_repos_message
        "This user has no private forks."
      end

      private

      def repos_of_interest
        user.private_repositories.forks.sort_by(&:name)
      end

    end
  end
end
