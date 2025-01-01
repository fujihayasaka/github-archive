# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillRepoNPPSettings < Base
      include GitHub::Memoizer

      CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"

      class SecretScanningRepos < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :secret_scanning_repos
      end

      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      iterate_over :database_table, params: {
            model_class: SecretScanningRepos,
            conditions: "lower_confidence_patterns_enabled = 1",
            columns: %i[],
          }

      sig { override.void }
      def after_initialize
        return unless arguments[:repo_ids].present?

        iterator = T.cast(self.iterator, Iterators::DatabaseTable)
        iterator.conditions += " and id IN (#{arguments[:repo_ids]})"
      end

      sig { returns(Integer) }
      memoize def ghost_id
        User.ghost&.id || 0
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        repo_level_configs = ConfigurationEntry.where(
          target_type: "Repository",
          target_id: items.keys,
          name: CONFIG_KEY_USER_ENABLED,
        ).pluck(:target_id, :value).to_h

        repos_without_repo_configs = items.keys - repo_level_configs.keys
        repos_with_false_repo_configs = repo_level_configs.select { |_id, value| value == "false" }.keys

        # insert rows
        configuration_rows = repos_without_repo_configs.map do |id|
          {
            target_type: "Repository",
            target_id: id,
            name: CONFIG_KEY_USER_ENABLED,
            value: "true",
            updater_id: ghost_id,
          }
        end

        if dry_run?
          log "Would have created #{configuration_rows.size} configurations"
        else
          ActiveRecord::Base.connected_to(role: :writing) do
            ConfigurationEntry.insert_all(configuration_rows)
          end
        end

        # update rows
        if dry_run?
          log "Would have updated #{repos_with_false_repo_configs.size} configurations"
        else
          write_to(model_class: ConfigurationEntry) do
            ConfigurationEntry.where(
              target_type: "Repository",
              target_id: repos_with_false_repo_configs,
              name: CONFIG_KEY_USER_ENABLED,
            ).update_all(value: "true", updater_id: ghost_id)
          end
        end

        log "Last repo id processed: #{items.keys.last}"
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(repo_ids))

  GitHub::Transitions::BackfillRepoNPPSettings.new(args).run
end
