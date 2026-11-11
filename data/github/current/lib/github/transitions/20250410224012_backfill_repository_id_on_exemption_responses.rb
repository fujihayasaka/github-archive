# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillRepositoryIdOnExemptionResponses < Base


      class ExemptionResponse < ApplicationRecord::Repositories
        self.table_name = :exemption_responses
      end

      iterate_over :database_table, params: {
        model_class: ExemptionResponse,
        conditions: "repository_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys

        scope = ExemptionResponse.where(id: ids)
        scope = scope.joins(Arel.sql(<<-SQL))
          INNER JOIN exemption_requests ON exemption_responses.exemption_request_id = exemption_requests.id
        SQL

        if dry_run?
          log "Dry run: would update repository_id for #{scope.count} exemption_responses, from #{ids.min} to #{ids.max}."
        else
          log "Updating repository_id for #{scope.count} exemption_responses, from #{ids.min} to #{ids.max}."
          write_to(model_class: ExemptionResponse) do
            scope.update_all(<<~SQL)
              exemption_responses.repository_id = exemption_requests.repository_id
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

  GitHub::Transitions::BackfillRepositoryIdOnExemptionResponses.new(args).run
end
