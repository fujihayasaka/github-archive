# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryDependabotAlertsThread < Platform::Objects::Base
      description "A wrapper on Repository used for Dependabot Alerts notifications."
      minimum_accepted_scopes ["public_repo"]

      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]

      implements Interfaces::RepositoryNode

      implements_node templates: [[:rdat, :repo_id, :id]], as: "RDAT", ready_date: Platform::Helpers::GlobalId::COHORT_4 do |repo_dep_alerts_thread|
        repo_dep_alerts_thread.async_repository.then do |repo|
          {
            prefix: :rdat,
            repo_id: repo.id,
            id: repo_dep_alerts_thread.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # The thread argument is a ::RepositoryDependabotAlertsThread instance.
      def self.async_api_can_access?(permission, thread)
        permission.async_can_read_vulnerability_alerts_thread?(thread)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.load_repo_and_owner(object).then do |repo|
          repo.vulnerability_alerts_visible_to?(permission.viewer)
        end
      end

      def self.load_from_global_id(id)
        ::RepositoryDependabotAlertsThread.find_by_id(id)
      end

      field :notifications_permalink, Scalars::URI, "The URL pointing to the repository's dependabot alerts page", null: true
    end
  end
end
