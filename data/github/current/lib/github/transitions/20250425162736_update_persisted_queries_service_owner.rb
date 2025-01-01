# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdatePersistedQueriesServiceOwner < Base
      # Environment-specific IDs from the prod console
      ENVIRONMENT_IDS = T.let({
        "dotcom" => { experience_id: 8, issues_id: 7 },
        "prod-ae-01" => { experience_id: 1, issues_id: 76 },
        "prod-sdc-01" => { experience_id: 1, issues_id: 72 },
        "prod-weu-01" => { experience_id: 16, issues_id: 11 },
        "prod-cus-01" => { experience_id: 86, issues_id: 126 },
        "staff-wus2-01" => { experience_id: 31, issues_id: 26 },
      }, T::Hash[String, T::Hash[Symbol, Integer]])

      #This is to prevent the use of the `GitHub::Config::Proxima` class in the test environment
      # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      CURRENT_ENVIRONMENT = T.let(Rails.env.test? ? "dotcom" : GitHub::Config::Proxima.current_stamp_or_dotcom, String)
      IDS = T.let(ENVIRONMENT_IDS[CURRENT_ENVIRONMENT], T.nilable(T::Hash[Symbol, Integer]))

      iterate_over :database_table, params: {
        model_class: Platform::OperationStore::ApplicationRecordBackend::GraphqlClientOperation,
        conditions: "graphql_client_id = #{IDS&.dig(:experience_id)}"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log("Processing #{items.count} persisted queries for environment #{CURRENT_ENVIRONMENT} with ids in range #{items.keys.first}..#{items.keys.last}")

        updated_count = 0

        batch_operations_ids = items.keys.uniq
        client_operations = Platform::OperationStore::ApplicationRecordBackend::GraphqlClientOperation.where(id: batch_operations_ids)

        if dry_run?
          log "Would be updating #{client_operations.size} persisted queries in this batch for environment #{CURRENT_ENVIRONMENT}"
          log "Batch_operations_ids: #{batch_operations_ids}"
          log "Client_operations: #{client_operations.map(&:graphql_client_id)}"
        else
          write_to(model_class: Platform::OperationStore::ApplicationRecordBackend::GraphqlClientOperation) do
            client_operations.each do |op|
              begin
                op.update!(graphql_client_id: IDS&.dig(:issues_id))
                updated_count += 1
              rescue ActiveRecord::RecordNotUnique => e
                log("Duplicate record error for operation with ID #{op.id} in environment #{CURRENT_ENVIRONMENT}: #{e.message}")
              end
            end

            log("Updated #{updated_count} persisted queries in this batch for environment #{CURRENT_ENVIRONMENT}") unless updated_count == 0
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

  GitHub::Transitions::UpdatePersistedQueriesServiceOwner.new(args).run
end
