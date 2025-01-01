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
        return false unless FeatureFlag.vexi.enabled?(:dependabot_repository_transfer_bulk_write_to_elasticsearch, repository, repository.owner, default: false)
        repository.vulnerability_alerts_enabled?
      end

      # Updates the dependabot alerts search index after a repository transfer.
      # This change does not result in any updates to the `search_index_updated_at` timestamp.
      sig { params(repository: ::Repository).void }
      def self.synchronize_repository_transfer(repository)
        BulkUpdateSearchIndexJob.perform_later(
          filters: { repository_id: repository.id },
          attributes: dependabot_alert_fields(repository),
          updated_at: nil,
          log_tags: { "gh.repository.id" => repository.id, "gh.owner.id" => repository.owner_id },
          stats_tags: ["source:repository_transfer"]
        )
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
      sig { params(repository: ::Repositories::IRepository).returns(T::Boolean) }
      def self.synchronize_dependabot_alerts_enablement_change?(repository)
        FeatureFlag.vexi.enabled?(:dependabot_write_enablement_change_to_elasticsearch, repository, repository.owner, default: false)
      end

      # Start a job to synchronize the Dependabot Alerts search index after
      # dependabot alerts is enabled on a repository.
      sig { params(repository: ::Repositories::IRepository).void }
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
      sig { params(repository: ::Repositories::IRepository).void }
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
