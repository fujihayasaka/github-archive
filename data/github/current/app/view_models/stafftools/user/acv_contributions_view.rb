# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class AcvContributionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :user

      def page_title
        "#{user.login} - Arctic Code Vault Contributions"
      end

      def top_acv_contributions
        @top_acv_contributions ||= all_acv_contributions.where({
          repository_id: user.top_acv_repositories.pluck(:id)
        })
      end

      def all_acv_contributions
        @all_acv_contributions ||= AcvContributor.includes_ignored(user.all_emails)
      end
    end
  end
end
