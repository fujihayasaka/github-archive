# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions

    class MigrateDependabotActionsBetaFFToConfig < Base
      include GitHub::Memoizer

      class Repository < ApplicationRecord::Domain::Repositories
        self.table_name = "repositories"
      end

      class ConfigurationEntries < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      DEPENDABOT_ON_ACTIONS_ENABLED = "repository_dependency_updates.actions_runner.enabled"
      DEPENDABOT_SELF_HOSTED_ENABLED = "repository_dependency_updates.self_hosted.enabled"

      sig { returns(Integer) }
      memoize def ghost_id
        User.ghost&.id || 0
      end

      sig { override.void }
      def after_initialize
        @iterator = Iterators::Csv.new(csv_file: arguments[:file_name], csv_read_opts: { headers: true })
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)

        log "#{dry_run? ? "Would be migrating" : "Migrating"} repos from #{items.keys.first} to #{items.keys.last}"
        configuration_rows = []
        migration_count = 0
        self_hosted_count = 0
        batch_repo_ids = items.values.map { |row| row[:repo_id] }

        dependabot_on_actions_enabled_config = get_dependabot_on_actions_enabled_config(batch_repo_ids)
        process_items(items, dependabot_on_actions_enabled_config, configuration_rows)
      end

      private

      sig { params(batch_repo_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def  get_dependabot_on_actions_enabled_config(batch_repo_ids)
        ConfigurationEntries.where(
          target_type: "Repository",
          target_id: batch_repo_ids,
          name: DEPENDABOT_ON_ACTIONS_ENABLED,
          value: "true").pluck(:target_id)
      end

      sig do
        params(
          items: Iterators::Items,
          dependabot_on_actions_enabled_config: T::Array[Integer],
          configuration_rows: T::Array[T::Hash[Symbol, T.untyped]],
        ).void
      end
      def process_items(items, dependabot_on_actions_enabled_config, configuration_rows)
        migration_count = 0
        self_hosted_count = 0
        items.each do |(_, row)|
          repo_id = row[:repo_id].to_i

          if dependabot_on_actions_enabled_config.include?(repo_id)
            log "Repo with repo id #{repo_id} already migrated"
            next
          end

          log "#{dry_run? ? "Would be migrating" : "Migrating"} repo with repo id #{repo_id}"
          configuration_rows.push(
            {
              target_type: "Repository",
              target_id: repo_id,
              name: DEPENDABOT_ON_ACTIONS_ENABLED,
              value: "true",
              updater_id: ghost_id,
            }
          )
          migration_count += 1
          if row[:self_hosted_enabled] == "true"
            configuration_rows.push(
              {
                target_type: "Repository",
                target_id: repo_id,
                name: DEPENDABOT_SELF_HOSTED_ENABLED,
                value: "true",
                updater_id: ghost_id,
              }
            )
            self_hosted_count += 1
          end
        end

        unless dry_run?
          write_to(model_class: ConfigurationEntries) do
            ConfigurationEntries.insert_all(configuration_rows)
          end
        end

        log_migration_end(migration_count, self_hosted_count)
      end

      sig { params(migration_count: Integer, self_hosted_count: Integer).void }
      def log_migration_end(migration_count, self_hosted_count)
        log "#{dry_run? ? "Would have enabled" : "Enabled"} a total of #{migration_count - self_hosted_count} GitHub hosted runners."
        log "#{dry_run? ? "Would have enabled" : "Enabled"} a total of #{self_hosted_count} self hosted repos"
        log "#{dry_run? ? "Would have migrated" : "Migrated"} a total of #{migration_count} repos to dependabot_on_actions"
        log "end of batch"
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(file_name))

  GitHub::Transitions::MigrateDependabotActionsBetaFFToConfig.new(args).run
end
