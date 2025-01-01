# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class MostPrevalentRulesQuery < AbstractQuery
          extend T::Helpers
          include GitHub::SecurityCenter::LoggingHelper

          class ListItem < T::Struct
            const :ruleName, String
            const :ruleSarifIdentifier, String
            const :count, Integer
          end

          class Result < T::Struct
            const :items, T::Array[ListItem]
            const :previous, T.nilable(String)
            const :next, T.nilable(String)
          end

          sig { params(cursor: String, page_size: Integer).returns(Result) }
          def perform(cursor:, page_size:)
            offset = T.let(Integer(cursor, exception: false), T.nilable(Integer))
            raise ArgumentError, "Unexpected `cursor` input." if offset.nil? || offset < 0

            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .select(
                Arel.sql("`#{CodeScanningPullRequestAlert.table_name}`.`rule_sarif_identifier`"),
                Arel.sql("`#{CodeScanningPullRequestAlert.table_name}`.`repository_id` as sample_repository_id"),
                Arel.sql("`#{CodeScanningPullRequestAlert.table_name}`.`alert_number` as sample_alert_number"),
                Arel.sql("COUNT(*) as alert_count"),
              )
              .group(:rule_sarif_identifier)
              .order(alert_count: :desc, rule_sarif_identifier: :asc)
              .limit(page_size + 1) # to know if there's more
              .offset(offset)

            db_results = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(query)
              .map { |row| row.to_hash.symbolize_keys }

            rule_sarif_to_name = get_rule_names_from_turboscan(
              db_results.map do |row|
                {
                  rule_sarif_identifier: row[:rule_sarif_identifier],
                  repository_id: row[:sample_repository_id],
                  alert_number: row[:sample_alert_number],
                }
              end
            )

            items = T.let([], T::Array[ListItem])
            is_last_page = T.let(true, T::Boolean)

            db_results.each_with_index do |row, index|
              if index >= page_size
                is_last_page = false
                next # stop once we hit the page limit
              end

              rule_name = rule_sarif_to_name[row[:rule_sarif_identifier]]

              items << ListItem.new(
                ruleSarifIdentifier: row[:rule_sarif_identifier],
                ruleName: rule_name || "Unknown rule",
                count: row[:alert_count]&.to_i || 0,
              )
            end

            previous_page = offset <= page_size ? 0 : offset - page_size unless offset.zero?
            next_page = is_last_page ? nil : offset + page_size
            Result.new(
              items:,
              previous: previous_page&.to_s,
              next: next_page&.to_s
            )
          end

          private

          sig do
            params(
              samples: T::Array[{
                rule_sarif_identifier: String,
                repository_id: Integer,
                alert_number: Integer,
              }]
            ).returns(T::Hash[String, String])
          end
          def get_rule_names_from_turboscan(samples)
            async_results = samples.map do |sample|
              sample => { repository_id:, alert_number:, rule_sarif_identifier: }
              Platform::Loaders::Turboscan::CodeScanningShortAlerts
                .load(repository_id, alert_number)
                .then do |short_alert|
                  [rule_sarif_identifier, short_alert&.fetch(:title)]
                end
            end

            Promise.all(async_results).sync.to_h
          end

          instrument_method \
            :perform,
            :get_rule_names_from_turboscan
        end
      end
    end
  end
end
