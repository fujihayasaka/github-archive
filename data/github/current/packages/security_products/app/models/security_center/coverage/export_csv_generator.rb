# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class ExportCsvGenerator
      extend T::Sig

      TEAM_COUNT_CAP = 20

      sig { params(query_results: T::Array[ExportDataQuery::RepositoryRowResult]).returns(String) }
      def self.generate(query_results)
        headers = [
          "Organization",
          "Name",
          "Archived",
          "Updated At",
          "Visibility",
          "Dependabot Alerts Status",
          "Dependabot Security Updates Status",
          "Code Scanning Alerts Status",
          "Code Scanning Pull Request Alerts Status",
          "Code Scanning Default Setup Status",
          "Secret Scanning Alerts Status",
          "Secret Scanning Push Protection Status",
          "Advanced Security Status",
          "Topics",
          "Teams (truncated at #{TEAM_COUNT_CAP} values)"
        ]

        CSV.generate(write_headers: true, headers:) do |csv|
          query_results.each do |row|
            org, name = row.name_with_display_owner.split("/")
            csv << [
              org,
              name,
              row.archived,
              row.updated_at,
              row.visibility,
              row.dependabot_alerts_status,
              row.dependabot_security_updates_status,
              row.code_scanning_alerts_status,
              row.code_scanning_pull_request_alerts_status,
              row.code_scanning_default_setup,
              row.secret_scanning_alerts_status,
              row.secret_scanning_push_protection_status,
              row.advanced_security_status,
              (%{["#{row.topics.sort.join('","')}"]} if row.topics.present?),
              (%{["#{row.teams.sort.first(TEAM_COUNT_CAP).join('","')}"]} if row.teams.present?)
            ]
          end
        end
      end
    end
  end
end
