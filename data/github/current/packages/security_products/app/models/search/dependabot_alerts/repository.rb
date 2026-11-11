# typed: strict
# frozen_string_literal: true

module Search
  module DependabotAlerts
    module Repository
      extend T::Helpers

      # Returns a repository's data to index in Elasticsearch for Dependabot Alerts.
      sig { params(repository: ::Repository).returns(T::Hash[Symbol, T.untyped]) }
      def self.dependabot_alert_fields(repository)
        {
          repository_id: repository.id,
          owner_id: repository.owner_id,
        }
      end

      # Returns true if the Dependabot Alerts search index should be updated after a repository
      # transfer.
      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.synchronize_repository_transfer?(repository)
        return false unless GitHub.dependabot_es_search_enabled?

        repository.vulnerability_alerts_enabled?
      end

      # Updates the dependabot alerts search index after a repository transfer.
      # This change does not result in any updates to the `search_index_updated_at` timestamp.
      sig { params(repository: ::Repository).void }
      def self.synchronize_repository_transfer(repository)
        AddToSearchIndexJob.perform_later("bulk_dependabot_alerts", repository.id)
      rescue StandardError => e
        Failbot.report(
          e,
          "code.namespace" => self.name,
          "code.function" => __method__,
          "gh.repository.id" => repository.id,
          "gh.owner.id" => repository.owner_id,
        )
      end

      # Returns true if the Dependabot Alerts search index should be updated after
      # dependabot alerts is enabled or disabled on a repository.
      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.synchronize_dependabot_alerts_enablement_change?(repository)
        GitHub.dependabot_es_search_enabled?
      end

      # Returns true if Dependabot Alerts should be removed from the search index
      # after a repository is unarchived or restored.
      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.add_alerts_on_repository_unarchived_or_restored?(repository)
        return false unless GitHub.dependabot_es_search_enabled?
        repository.vulnerability_alerts_enabled?
      end

      # Returns true if Dependabot Alerts should be removed from the search index
      # after a repository is archived or deleted.
      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.remove_alerts_on_repository_archived_or_deleted?(repository)
        return false unless GitHub.dependabot_es_search_enabled?
        # We should not do any processing to remove alerts when we know that they are not already present
        # in elasticsearch.  We would normally check Repository#vulnerability_alerts_enabled? here, but
        # that will return false for archived or deleted repositories, and this function is called
        # specifically in response to those status changes.
        # Instead, we check the repo's underlying vulnerability alerts configurable value without the
        # archived or deleted checks because we know that one of those checks will now return false.
        SecurityProduct::VulnerabilityAlerts.new(repository).config_enabled?
      end

      # Start a job to synchronize the Dependabot Alerts search index after
      # dependabot alerts is enabled on a repository.
      sig { params(repository: ::Repository).void }
      def self.synchronize_dependabot_alerts_enabled(repository)
        AddToSearchIndexJob.perform_later("bulk_dependabot_alerts", repository.id)
      rescue StandardError => e
        Failbot.report(
          e,
          "code.namespace" => self.name,
          "code.function" => __method__,
          "gh.repository.id" => repository.id,
          "gh.owner.id" => repository.owner_id,
        )
      end

      # Start a job to synchronize the Dependabot Alerts search index after
      # dependabot alerts is disabled on a repository.
      sig { params(repository: ::Repository).void }
      def self.synchronize_dependabot_alerts_disabled(repository)
        RemoveFromSearchIndexJob.perform_later("bulk_dependabot_alerts", repository.id)
      rescue StandardError => e
        Failbot.report(
          e,
          "code.namespace" => self.name,
          "code.function" => __method__,
          "gh.repository.id" => repository.id,
          "gh.owner.id" => repository.owner_id,
        )
      end
    end
  end
end
