# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module OverviewDashboard
    class ExportCsvGenerator
      ELEMENT_COUNT_CAP = 20

      BASE_HEADERS = T.let([
        "Repository",
        "Repository ID",
        "Tool",
        "Alert Number",
        "Severity",
        "Created At",
        "Updated At",
        "Resolved At",
        "Reopened At",
        "Resolved Reason",
        "Secret Bypassed",
        "Secret Type",
        "Secret Provider",
        "Secret Validity",
        "GHSA ID",
        "Ecosystem",
        "Package",
        "Dependency Scope",
        "CodeQL Rule",
        "Third Party Tool Rule",
        "Teams (truncated at #{ELEMENT_COUNT_CAP} values)",
        "Repository Visibility",
        "Repository Topics",
        "Repository Archived"
      ].freeze, T::Array[String])

      sig { params(query_results: T::Array[{}], property_headers: T.nilable(T::Array[String]), write_headers: T::Boolean).returns(String) }
      def self.generate(query_results, property_headers, write_headers = true)
        property_headers&.sort! # we rely on this being in a consistent order between setting headers and assigning values

        headers = BASE_HEADERS.dup
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
          query_results.each do |row|
            results = [
              row["repository_nwo"],
              row["repository_id"],
              row["tool"],
              row["alert_number"],
              row["alert_severity"],
              row["alert_created_at"],
              row["alert_updated_at"],
              row["alert_resolved_at"],
              row["alert_reopened_at"],
              row["alert_resolution"],
              row["alert_bypassed"],
              row["alert_type"],
              row["alert_type_provider"],
              row["alert_validity"],
              row["ghsa_id"],
              row["ecosystem"],
              row["package_name"],
              row["dependency_scope"],
              row["codeql_tool"],
              row["third_party_tool"],
              row["teams"]&.sort&.first(ELEMENT_COUNT_CAP),
              row["visibility"],
              row["repo_topics"]&.sort,
              row["archived"],
            ]

            property_headers&.each do |property|
              property_values = row.with_indifferent_access.dig("repo_properties", property)
              if property_values.is_a?(Array)
                property_values = property_values.sort.first(ELEMENT_COUNT_CAP)
              end

              results << property_values
            end

            csv << results
          end
        end
      end
    end
  end
end
