# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "dependency_graph/base_twirp_client"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillDependencyScopeForGhesRepos < Base
      class Repository < ApplicationRecord::Domain::Repositories
        self.table_name = :repositories
      end

      iterate_over :database_table, params: {
        model_class: Repository,
        columns: [:id],
        conditions: "active = 1"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        repo_ids_with_alert_counts = RepositoryVulnerabilityAlert.where(repository_id: items.keys, state: 0).group(:repository_id).count
        repo_ids_with_alert_counts.select! { |_, alert_count| alert_count > 0 }

        repo_ids_with_alert_counts.each do |repository_id, _|
          options = { skip_notifications: true }

          UpdateRepositoryVulnerabilityAlertsJob.
            set(queue: "dependabot_alerts_backfill").
            perform_later(repository_id, options)
        end

        log "Enqueued #{repo_ids_with_alert_counts.keys.size} UpdateRepositoryVulnerabilityAlertJob jobs" if verbose?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillDependencyScopeForGhesRepos.new(args).run
end
