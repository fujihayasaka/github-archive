# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class CsvGeneratorTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
      end

      test "formats data correctly" do
        fake_data = []
        5.times do |i|
          fake_data << ExportDataQuery::RepositoryRowResult.new(
            name_with_display_owner: "org-login/repo-#{i}",
            archived: false,
            updated_at: "date-string",
            visibility: "private",
            dependabot_alerts_count: 1,
            code_scanning_alerts_count: 2,
            secret_scanning_alerts_count: 3,
            topics: %w[topic-1 topic-2],
            teams: ["team-1", "team-2", "team-with,comma"],
          )
        end

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo-0,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-1,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-2,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-3,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-4,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "handles nil data" do
        fake_data = [ExportDataQuery::RepositoryRowResult.new(
          name_with_display_owner: "org-login/repo",
          archived: false,
          updated_at: "date-string",
          visibility: nil,
          dependabot_alerts_count: nil,
          code_scanning_alerts_count: nil,
          secret_scanning_alerts_count: nil,
          topics: [],
          teams: [],
        )]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          "org-login,repo,false,date-string,,,,,,",
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "sorts teams and topics alphabetically" do
        fake_data = [ExportDataQuery::RepositoryRowResult.new(
          name_with_display_owner: "org-login/repo",
          archived: false,
          updated_at: "date-string",
          visibility: "private",
          dependabot_alerts_count: 1,
          code_scanning_alerts_count: 2,
          secret_scanning_alerts_count: 3,
          topics: %w[topic-z topic-a],
          teams: %w[team-z team-a],
        )]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,1,2,3,"[""topic-a"",""topic-z""]","[""team-a"",""team-z""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "limits number of teams per repo" do
        teams = (ExportCsvGenerator::TEAM_COUNT_CAP + 1).times.map { |i| "team-#{i}" }
        fake_data = [ExportDataQuery::RepositoryRowResult.new(
          name_with_display_owner: "org-login/repo",
          archived: false,
          updated_at: "date-string",
          visibility: "private",
          dependabot_alerts_count: 1,
          code_scanning_alerts_count: 2,
          secret_scanning_alerts_count: 3,
          topics: [],
          teams: teams,
        )]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,1,2,3,,"[""#{teams.sort.first(ExportCsvGenerator::TEAM_COUNT_CAP).join("\"\",\"\"")}""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end
    end
  end
end
