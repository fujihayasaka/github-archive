# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      class ExportCsvGenerator
        extend T::Sig

        ELEMENT_COUNT_CAP = 20

        HEADERS = T.let([
          "Repository",
          "Repository ID",
          "Pull Request Number",
          "Pull Request URL",
          "Alert Number",
          "Severity",
          "CodeQL Rule",
          "Created At",
          "Updated At",
          "Resolved At",
          "Resolved Reason",
          "Has Autofix",
          "Autofix Accepted",
          "Repository Visibility",
          "Repository Archived",
          "Teams (truncated at #{ELEMENT_COUNT_CAP} values)",
          "Repository Topics",
          # headers for repository custom properties are added dynamically
        ].freeze, T::Array[String])

        sig do
          params(
            results: Queries::DataExportQuery::Result,
            write_headers: T::Boolean,
          ).returns(String)
        end
        def self.generate(results, write_headers = true)
          headers = HEADERS.dup

          # Add headers for repository custom properties.
          # Each record contains a hash of _all_ custom properties,
          # even if that particular alert's repository doesn't have a value.
          # No need to cap the results, an org can only have 100 properties.
          results.items.first&.repository_properties&.sort&.each do |key, _|
            headers << "Custom Property: #{key}"
          end

          list_field_converter = proc do |value|
            if value.is_a?(Array)
              # Quote each value, comma separate them, wrap that in brackets, then quote the whole thing
              # "["apple","banana","pear"]"
              %{["#{value.join('","')}"]} if value.present?
            else
              value
            end
          end
          write_converters = [list_field_converter]

          CSV.generate(write_headers:, headers:, write_converters:) do |csv|
            results.items.each do |result|
              row = [
                result.repository_nwo,
                result.repository_id,
                result.pull_request_number,
                result.pull_request_url,
                result.alert_number,
                result.severity,
                result.rule_sarif_identifier,
                result.created_at,
                result.updated_at,
                result.resolved_at,
                result.resolved_reason,
                result.has_autofix,
                result.autofix_accepted,
                result.repository_visibility,
                result.repository_archived,
                result.repository_teams.sort.first(ELEMENT_COUNT_CAP),
                result.repository_topics.sort,
              ]

              result.repository_properties.sort.each do |_, property_values|
                row << property_values
              end

              csv << row
            end
          end
        end
      end
    end
  end
end
