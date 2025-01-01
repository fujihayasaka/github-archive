# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      class ExportCsvGenerator

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
            property_headers: T.nilable(T::Array[String]),
            write_headers: T::Boolean,
          ).returns(String)
        end
        def self.generate(results, property_headers, write_headers = true)
          property_headers&.sort! # we rely on this being in a consistent order between setting headers and assigning values

          headers = HEADERS.dup
          property_headers&.each do |property|
            headers << "Custom Property: #{property}"
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

              property_headers&.each do |property|
                property_values = result.repository_properties.with_indifferent_access[property]
                if property_values.is_a?(Array)
                  property_values = property_values.sort.first(ELEMENT_COUNT_CAP)
                end

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
