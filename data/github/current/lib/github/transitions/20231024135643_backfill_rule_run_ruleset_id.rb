# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillRuleRunRulesetId < Base

      class RuleRun < ApplicationRecord::Domain::RuleInsights
        self.table_name = :repository_rule_runs
        default_scope { annotate("cross-shard-query-exempted") }
      end

      iterate_over :database_table, params: {
        model_class: RuleRun,
        conditions: "repository_rule_configuration_id IS NOT NULL AND rule_provider_id IS NULL",
        columns: [:repository_rule_configuration_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        config_ids = items.values.map { |v| v[:repository_rule_configuration_id] }.compact.uniq
        configs_by_id = RepositoryRuleConfiguration.where(id: config_ids).to_h { |config| [config.id, config] }
        items.each do |id, values|
          config = configs_by_id[values[:repository_rule_configuration_id]]
          if config && config.repository_ruleset_id
            if dry_run?
              log "Would have updated RuleRun id:#{id} with ruleset ID #{config.repository_ruleset_id}."
            else
              write_to(model_class: RuleRun) do
                GitHub::SQLCheckers::TableSharding.allowing_cross_shard_queries do
                  RuleRun.where(id: id).update_all(rule_provider_id: config.repository_ruleset_id, rule_provider: "repository_ruleset")
                end
              end
              log "Updated RuleRun id:#{id} with ruleset ID #{config.repository_ruleset_id}."
            end
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

  GitHub::Transitions::BackfillRuleRunRulesetId.new(args).run
end
