# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillRuleSuiteOwnerId < Base
      class RuleSuite < ApplicationRecord::Repositories
        self.table_name = :repository_rule_suites
      end

      iterate_over :database_table, params: {
        model_class: RuleSuite,
        columns: [:id, :repository_id],
        conditions: "owner_id IS NULL"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys
        repo_ids = items.values.map { |v| v[:repository_id] }.compact.uniq
        owner_ids = Repository.where(id: repo_ids).pluck(:id, :owner_id).to_h

        # for each rulesuite, add the owner_id to the hash, and remove the repo id from the hash
        items.each do |_id, values|
          values[:owner_id] = owner_ids[values[:repository_id]]
          values.delete(:repository_id)
        end

        # bulk update all the rulesuites with the owner_id
        if dry_run?
          log "Dry run. Rulesuite id #{items.keys.first}"
        else
          log "Updating Rulesuite id #{items.keys.first}"
          write_to(model_class: RuleSuite) do
            RuleSuite.update(items.keys, items.values)
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

  GitHub::Transitions::BackfillRuleSuiteOwnerId.new(args).run
end
