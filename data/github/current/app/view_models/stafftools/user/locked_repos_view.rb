# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class LockedReposView < ReposView

      def page_title
        "#{user.login} - Locked repositories"
      end

      def no_repos_message
        "This user has no locked repositories."
      end

      private

      def repos_of_interest
        user.repositories.locked_repos.order(:name)
      end
    end
  end
end
