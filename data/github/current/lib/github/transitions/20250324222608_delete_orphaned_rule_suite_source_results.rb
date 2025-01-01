# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteOrphanedRuleSuiteSourceResults < Base
      class RepositoryRuleSuiteSourceResult < ApplicationRecord::RepositoriesPushes
        self.table_name = :repository_rule_suite_source_results
        default_scope { annotate("cross-shard-query-exempted") }
      end

      iterate_over :database_table, params: {
        model_class: RepositoryRuleSuiteSourceResult,
        conditions: "repository_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys

        scope = RepositoryRuleSuiteSourceResult.where(id: ids)
        scope = scope.joins(Arel.sql(<<-SQL))
          LEFT OUTER JOIN repository_rule_suites ON repository_rule_suite_source_results.repository_rule_suite_id = repository_rule_suites.id
        SQL
        .where(Arel.sql("repository_rule_suites.id IS NULL"))

        orphaned_source_result_ids = scope.pluck(:id)

        if dry_run?
          log "Dry run: would delete #{scope.count} repository_rule_suite_source_results, from #{ids.min} to #{ids.max}."
        else
          log "Deleting #{scope.count} repository_rule_suite_source_results, from #{ids.min} to #{ids.max}."
          write_to(model_class: RepositoryRuleSuiteSourceResult) do
            scope.delete_all
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

  GitHub::Transitions::DeleteOrphanedRuleSuiteSourceResults.new(args).run
end
