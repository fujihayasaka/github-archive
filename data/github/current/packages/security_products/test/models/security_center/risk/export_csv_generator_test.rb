# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class CsvGeneratorTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
      end

      setup do
        ::SecurityCenter::FeatureFlagHelper.stubs(:enterprise_risk_csv_export?).returns(false)
        ::SecurityCenter::FeatureFlagHelper.stubs(:risk_export_include_repo_properties?).returns(true)
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

        csv = ExportCsvGenerator.generate(fake_data, property_headers: [])

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
          %{org-login,repo-0,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-1,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-2,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-3,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-4,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "Includes owner type in new headers if enterprise flag is enabled" do
        ::SecurityCenter::FeatureFlagHelper.stubs(:enterprise_risk_csv_export?).returns(true)

        fake_data = []
        5.times do |i|
          fake_data << ExportDataQuery::RepositoryRowResult.new(
            name_with_display_owner: "org-login/repo-#{i}",
            owner_type: "ORGANIZATION",
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

        csv = ExportCsvGenerator.generate(fake_data, property_headers: [], owner: @org)

        expected_csv = [
          "Owner,Repository,Owner type,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
          %{org-login,repo-0,ORGANIZATION,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-1,ORGANIZATION,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-2,ORGANIZATION,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-3,ORGANIZATION,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
          %{org-login,repo-4,ORGANIZATION,false,date-string,private,1,2,3,"[""topic-1"",""topic-2""]","[""team-1"",""team-2"",""team-with,comma""]"},
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

        csv = ExportCsvGenerator.generate(fake_data, property_headers: [])

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
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

        csv = ExportCsvGenerator.generate(fake_data, property_headers: [])

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,1,2,3,"[""topic-a"",""topic-z""]","[""team-a"",""team-z""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "limits number of teams per repo" do
        teams = (ExportCsvGenerator::ELEMENT_COUNT_CAP + 1).times.map { |i| "team-#{i}" }
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

        csv = ExportCsvGenerator.generate(fake_data, property_headers: [])

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
          %{org-login,repo,false,date-string,private,1,2,3,,"[""#{teams.sort.first(ExportCsvGenerator::ELEMENT_COUNT_CAP).join("\"\",\"\"")}""]"},
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "includes repository properties" do
        repository_properties = {
          "single-select" => nil,
          "multi-select" => %w[one two],
          "boolean" => nil,
          "string" => "woof",
        }

        fake_data = [
          SecurityOverviewAnalytics::Risk::ExportQuery::ListItem.new(
            name_with_display_owner: "org-login/repo-a",
            archived: false,
            updated_at: "date-string",
            visibility: "private",
            dependabot_alerts_count: 1,
            code_scanning_alerts_count: 2,
            secret_scanning_alerts_count: 3,
            topics: [],
            teams: [],
            repository_properties:,
          )
        ]

        csv = ExportCsvGenerator.generate(fake_data, property_headers: repository_properties.keys)

        expected_csv = [
          "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Count,Code Scanning Alerts Count,Secret Scanning Alerts Count,Topics,Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values),#{repository_properties.keys.sort.map { |key| "Custom Property: #{key}" }.join(",")}",
          "org-login,repo-a,false,date-string,private,1,2,3,,,,\"[\"\"one\"\",\"\"two\"\"]\",,woof"
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end
    end
  end
end
