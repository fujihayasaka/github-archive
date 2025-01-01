# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module OverviewDashboard
    class ExportCsvGenerator
      extend T::Sig

      ELEMENT_COUNT_CAP = 20

      sig { params(query_results: T::Array[{}], include_headers: T::Boolean).returns(String) }
      def self.generate(query_results, include_headers = true)
        headers = [
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
        ]

        # We can use the first one because each repo's "repo_properties" is a hash of all repo properties, including ones not set on that repo.
        # We don't need to cap the list of repo properties because there's already a limit of 100 per org
        query_results.first&.dig("repo_properties")&.keys&.sort&.each do |key|
          headers << "Custom Property: #{key}"
        end

        CSV.generate(write_headers: include_headers, headers:) do |csv|
          query_results.each do |row|
            alert_severity = row["alert_severity"]&.downcase
            alert_severity = "medium" if alert_severity == "moderate"

            alert_bypassed = ActiveModel::Type::Boolean.new.cast(row["alert_bypassed"]).to_s if row["alert_bypassed"].present?
            codeql_tool = (row["tool"] == "CodeQL" ? row["rule_sarif_identifier"] : nil)
            third_party_tool = (row["tool"] == "CodeQL" ? nil : row["rule_sarif_identifier"])
            teams = %{["#{row["teams"].sort.first(ELEMENT_COUNT_CAP).join('","')}"]} if row["teams"].present?
            repo_visibility = SecurityOverviewAnalytics::Repository.visibilities.key(row["visibility"])
            repo_topics = %{["#{row["repo_topics"].sort.join('","')}"]} if row["repo_topics"].present?
            repo_archived = ActiveModel::Type::Boolean.new.cast(row["archived"]).to_s
            if row["alert_validity"].present?
              # TODO: we have validity values of 5 that should be 4 (TOKEN_VALIDITY_UNVERIFIABLE) https://github.com/github/security-center/issues/5472
              validity_enum = row["alert_validity"] == 5 ? 4 : row["alert_validity"]

              secret_validity = SecurityOverviewAnalytics::SecretScanningAlertRevision::VALIDITIES_MAPPING.select do |validity_name, validity_values|
                validity_name if validity_values.include?(validity_enum)
              end.keys.first
            end

            if row["alert_resolution"]
              mapping = case row["tool"]
              when "dependabot"
                SecurityOverviewAnalytics::DependabotAlertRevision::RESOLUTIONS_MAPPING
              when "secret-scanning"
                SecurityOverviewAnalytics::SecretScanningAlertRevision::RESOLUTIONS_MAPPING
              else
                SecurityOverviewAnalytics::CodeScanningAlertRevision::RESOLUTIONS_MAPPING
              end

              alert_resolution = mapping.select do |resolution_name, resolution_values|
                resolution_name if resolution_values.include?(row["alert_resolution"])
              end.keys.first
            end

            results = [
              row["name"],
              row["repository_id"],
              row["tool"],
              row["alert_number"],
              alert_severity,
              row["alert_created_at"],
              row["alert_updated_at"],
              row["alert_resolved_at"],
              row["alert_reopened_at"],
              alert_resolution,
              alert_bypassed,
              row["alert_type"],
              row["alert_type_provider"],
              secret_validity,
              row["ghsa_id"],
              row["ecosystem"],
              row["package_name"],
              row["dependency_scope"],
              codeql_tool,
              third_party_tool,
              teams,
              repo_visibility,
              repo_topics,
              repo_archived,
            ]

            row["repo_properties"]&.sort&.each do |_, property_values|
              if property_values.is_a?(Array)
                property_values = %{["#{property_values.sort.first(ELEMENT_COUNT_CAP).join('","')}"]}
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
