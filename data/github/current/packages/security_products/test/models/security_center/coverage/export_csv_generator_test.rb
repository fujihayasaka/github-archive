# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class CsvGeneratorTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
      end

      test "formats data correctly" do
        fake_data = []
        5.times do |i|
          fake_data << result(
            name_with_display_owner: "org-login/repo-#{i}",
            topics: %w[topic-1 topic-2],
            teams: ["team-1", "team-2", "team-with,comma"],
          )
        end

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo-0,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-1,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-2,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-3,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-4,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "handles nil data" do
        fake_data = [result(
          dependabot_alerts_status: nil,
          dependabot_security_updates_status: nil,
          code_scanning_alerts_status: nil,
          code_scanning_pull_request_alerts_status: nil,
          code_scanning_default_setup: nil,
          secret_scanning_alerts_status: nil,
          secret_scanning_push_protection_status: nil,
          advanced_security_status: nil,
          topics: [],
          teams: [],
        )]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          "org-login,repo,false,date-string,private,,,,,,,,,,",
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "sorts teams and topics alphabetically" do
        fake_data = [result(topics: %w[topic-z topic-a], teams: %w[team-z team-a])]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,"[""topic-a"",""topic-z""]","[""team-a"",""team-z""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "limits number of teams per repo" do
        teams = (ExportCsvGenerator::TEAM_COUNT_CAP + 1).times.map { |i| "team-#{i}" }
        fake_data = [result(teams:)]

        csv = ExportCsvGenerator.generate(fake_data)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{ExportCsvGenerator::TEAM_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,enabled,enabled,enabled,enabled,enabled,enabled,enabled,enabled,,"[""#{teams.sort.first(ExportCsvGenerator::TEAM_COUNT_CAP).join("\"\",\"\"")}""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      private

      def result(
        name_with_display_owner: "org-login/repo",
        archived: false,
        updated_at: "date-string",
        visibility: "private",
        dependabot_alerts_status: "enabled",
        dependabot_security_updates_status: "enabled",
        code_scanning_alerts_status: "enabled",
        code_scanning_pull_request_alerts_status: "enabled",
        code_scanning_default_setup: "enabled",
        secret_scanning_alerts_status: "enabled",
        secret_scanning_push_protection_status: "enabled",
        advanced_security_status: "enabled",
        topics: [],
        teams: []
      )
        ExportDataQuery::RepositoryRowResult.new(
          name_with_display_owner:,
          archived:,
          updated_at:,
          visibility:,
          dependabot_alerts_status:,
          dependabot_security_updates_status:,
          code_scanning_alerts_status:,
          code_scanning_pull_request_alerts_status:,
          code_scanning_default_setup:,
          secret_scanning_alerts_status:,
          secret_scanning_push_protection_status:,
          advanced_security_status:,
          topics:,
          teams:,
        )
      end
    end
  end
end
