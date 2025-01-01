# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class DisabledReposView < ReposView

      def page_title
        "#{user.login} - Disabled repositories"
      end

      def no_repos_message
        "This user has no disabled repositories."
      end

      private

      def repos_of_interest
        user.repositories.where("disabled_at IS NOT NULL").order(:name)
      end

    end
  end
end
