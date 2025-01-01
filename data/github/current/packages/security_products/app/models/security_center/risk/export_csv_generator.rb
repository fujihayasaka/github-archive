# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
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
          "Dependabot Alerts Count",
          "Code Scanning Alerts Count",
          "Secret Scanning Alerts Count",
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
              row.dependabot_alerts_count,
              row.code_scanning_alerts_count,
              row.secret_scanning_alerts_count,
              (%{["#{row.topics.sort.join('","')}"]} if row.topics.present?),
              (%{["#{row.teams.sort.first(TEAM_COUNT_CAP).join('","')}"]} if row.teams.present?)
            ]
          end
        end
      end
    end
  end
end
