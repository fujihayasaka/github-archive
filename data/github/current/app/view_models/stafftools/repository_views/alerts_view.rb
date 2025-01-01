# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class AlertsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Dependabot alerts"
      end

      def authorized_count
        @authorized_count ||= users_and_teams.size
      end

      def authorized_limit
        "#{authorized_count.to_i}/#{::Repository::VulnerabilityManagement::MAX_AUTHORIZED_VULNERABILITY_USERS_OR_TEAMS}"
      end

      def users_and_teams
        repository.vulnerability_manager.authorized_users_and_teams
      end
    end
  end
end
