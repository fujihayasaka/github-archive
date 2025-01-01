# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class DatabricksIssue9713ExportPreparer < ExportPreparer

      private

      def exclude_projects
        return true if super

        repository.feature_enabled?(:octoshift_experimental_incremental_migrations_exclude_projects)
      end

      def add_milestones(repository)
        return if repository.feature_enabled?(:octoshift_experimental_incremental_migrations_exclude_milestones)

        super
      end

      def pull_request_ids_for_repository(repository)
        repository.issues.with_pull_requests.where(number: selected_issue_and_pull_request_numbers).pluck(:pull_request_id)
      end

      def issue_ids_for_repository(repository)
        repository.issues.without_pull_requests.where(number: selected_issue_and_pull_request_numbers).pluck(:id)
      end

      def all_issue_ids_for_repository(repository)
        repository.issues.where(number: selected_issue_and_pull_request_numbers).pluck(:id)
      end

      def selected_issue_and_pull_request_numbers
        value = GitHub::Migrator::KV.store.get("DatabricksIssue9713ExportPreparer-#{repository.name_with_display_owner}").value {}
        value.blank? ? [] : GitHub::JSON.parse(value)
      end
    end
  end
end
