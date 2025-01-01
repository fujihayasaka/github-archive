# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillRepositoryIdOnRuleRuns < Base

      class RepositoryRuleRun < ApplicationRecord::RepositoriesPushes
        self.table_name = :repository_rule_runs
        default_scope { annotate("cross-shard-query-exempted") }
      end

      iterate_over :database_table, params: {
        model_class: RepositoryRuleRun,
        conditions: "repository_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys

        scope = RepositoryRuleRun.where(id: ids)
        scope = scope.joins(Arel.sql(<<-SQL))
          INNER JOIN repository_rule_suites ON repository_rule_runs.repository_rule_suite_id = repository_rule_suites.id
        SQL

        if dry_run?
          log "Dry run: would update repository_id for #{scope.count} repository_rule_runs, from #{ids.min} to #{ids.max}."
        else
          log "Updating repository_id for #{scope.count} repository_rule_runs, from #{ids.min} to #{ids.max}."
          write_to(model_class: RepositoryRuleRun) do
            scope.update_all(<<~SQL)
              repository_rule_runs.repository_id = repository_rule_suites.repository_id
            SQL
          end
        end
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

  GitHub::Transitions::BackfillRepositoryIdOnRuleRuns.new(args).run
end
