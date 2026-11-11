# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CustomerPropensityData < Base
      include T::Sig

      BATCH_SIZE = 100

      # Overwrite the perform method because we only write new records to a KV table
      sig { override.void }
      def perform
        log(
          "Starting to process data from table " \
          "hive.data_science.copilot_experiment_project_phoenix_output_table_v3"
        )

        # Keep track of query start time to calculate query duration
        query_start_time = Time.now.utc

        offset = 0

        loop do
          query = build_propensity_query(BATCH_SIZE, offset)
          results = GitHub.presto.run_with_names(query)

          results ||= []

          break if results.empty?

          batch_perform(results)

          offset += BATCH_SIZE
        end

        # Log the duration of the batch processed
        time_elapsed = GitHub::Dogstats.duration(query_start_time, Time.now.utc)
        GitHub.dogstats.distribution("customer_propensity_data.query_duration", time_elapsed)
      end

      # We are not overriding the process_batch method to simplify the transition and prevent
      # writing another iterator.
      sig { params(results: T::Array[T::Hash[String, T.untyped]]).void }
      def batch_perform(results)
        log("Processing a batch of #{results.size} records")
        results.each do |result|
          key = "user_propensity/copilot_business/v1/#{result.fetch("user_id")}"

          value = {
            "org_id" => result.fetch("org_id"),
            "org_login" => result.fetch("org_login"),
            "org_propensity_score" => result.fetch("org_propensity_score"),
            "user_id" => result.fetch("user_id"),
            "group" => result.fetch("org_propensity_group"),
            "relationship_type" => result.fetch("relationship_type"),
            "is_treatment" => result.fetch("is_treatment"),
            "day" => result.fetch("day"),
          }

          # Check if the key already exists
          existing_record = Site::KV.store.get(key).value { nil }

          # Write to the active record like below IF the existing record is nil and next out of this item look iteration
          if existing_record.nil?
            if !dry_run?
              write_to(model_class: Site::KV::DataStore) do
                Site::KV.store.set(key, value.to_json, expires: 1.month.from_now)
              end
            end
            next
          end

          existing_record_data = JSON.parse(existing_record)

          # Update org_propensity_score if the new score is higher
          if result.fetch("org_propensity_score").to_f > existing_record_data.fetch("org_propensity_score").to_f
            value["org_propensity_score"] = result.fetch("org_propensity_score")
          end

          # Replace the record if existing relationship_type is "member" && new relationship_type is "owner"
          if !org_admin?(existing_record_data) && org_admin?(result)
            value["org_propensity_group"] = result.fetch("org_propensity_group")
            value["day"] = result.fetch("day")
          end

          value_json = value.to_json

          # Update or insert the record unless in dry_run? mode
          if !dry_run?
            write_to(model_class: Site::KV::DataStore) do
              Site::KV.store.set(key, value_json, expires: 1.month.from_now)
            end
          end
        end
      end

      private

      sig { params(member_data: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def org_admin?(member_data)
        relationship = member_data.fetch("relationship_type", nil)
        relationship == "billing_manager" || relationship == "owner"
      end

      sig { params(limit: Integer, offset: Integer).returns(String) }
      def build_propensity_query(limit, offset)
        %Q(
            SELECT *
            FROM hive.data_science.copilot_experiment_project_phoenix_output_table_v3
            WHERE day = '2025-02-02'
            AND is_treatment = TRUE
            OFFSET #{offset}
            LIMIT #{limit}
        )
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

  GitHub::Transitions::CustomerPropensityData.new(args).run
end
