# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module OverviewDashboard
    class CsvGeneratorTest < GitHub::TestCase
      include SecurityCenter::TestFixtures

      BASE_HEADERS = [
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
        "Teams (truncated at #{ExportCsvGenerator::ELEMENT_COUNT_CAP} values)",
        "Repository Visibility",
        "Repository Topics",
        "Repository Archived"
      ]

      DEFAULT_PROPERTIES = { "boolean": true, "text": "some-text", "multi-select": %w[apples pears bananas], "single-select": "onions" }

      fixtures do
        @org = create(:organization)

        create :custom_property_definition, :true_false, source: @org, property_name: "boolean"
        create :custom_property_definition, :string, source: @org, property_name: "text"
        create :custom_property_definition, :multi_select, source: @org, property_name: "multi-select", allowed_values: %w[apples pears bananas cherries oranges]
        create :custom_property_definition, :single_select, source: @org, property_name: "single-select", allowed_values: %w[onions carrots celery potatoes]
      end

      test "formats data correctly" do
        csv = ExportCsvGenerator.generate(generate_fake_data(number_of_alerts: 5), DEFAULT_PROPERTIES.keys)

        expected_csv = [
          (BASE_HEADERS + DEFAULT_PROPERTIES.keys.sort.map { |key| "Custom Property: #{key}" }).join(","),
          "org-name/repo-name,1,CodeQL,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "org-name/repo-name,1,CodeQL,2,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "org-name/repo-name,1,CodeQL,3,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "org-name/repo-name,1,CodeQL,4,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "org-name/repo-name,1,CodeQL,5,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text"
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "handles nil data" do
        csv = ExportCsvGenerator.generate(generate_fake_data(teams: nil, properties: nil, topics: nil), DEFAULT_PROPERTIES.keys)

        expected_csv = [
          (BASE_HEADERS + DEFAULT_PROPERTIES.keys.sort.map { |key| "Custom Property: #{key}" }).join(","),
          "org-name/repo-name,1,CodeQL,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,,private,,false,,,,"
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "limits number of teams per repo" do
        ExportCsvGenerator.stub_const(:ELEMENT_COUNT_CAP, 2) do
          csv = ExportCsvGenerator.generate(generate_fake_data(properties: nil, topics: nil), DEFAULT_PROPERTIES.keys)

          expected_csv = [
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived,Custom Property: boolean,Custom Property: multi-select,Custom Property: single-select,Custom Property: text",
            "org-name/repo-name,1,CodeQL,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\"]\",private,,false,,,,",
          ].join("\n") + "\n"

          assert_equal expected_csv, csv
        end
      end

      test "limits number of property multiselect elements per repo" do
        ExportCsvGenerator.stub_const(:ELEMENT_COUNT_CAP, 2) do
          csv = ExportCsvGenerator.generate(generate_fake_data(teams: nil, topics: nil, properties: { "multi-select": %w[apples pears bananas] }), DEFAULT_PROPERTIES.keys)

          expected_csv = [
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived,Custom Property: boolean,Custom Property: multi-select,Custom Property: single-select,Custom Property: text",
            "org-name/repo-name,1,CodeQL,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,,private,,false,,\"[\"\"apples\"\",\"\"bananas\"\"]\",,",
          ].join("\n") + "\n"

          assert_equal expected_csv, csv
        end
      end

      test "custom properties are ordered correctly in the CSV" do
        # properties are in a different order than the CSV headers. Test that they're correctly assigned to the right CSV columns.
        properties = { "text": "some-text", "boolean": true, "single-select": "onions", "multi-select": %w[apples bananas] }
        csv = ExportCsvGenerator.generate(generate_fake_data(teams: nil, topics: nil, properties:), DEFAULT_PROPERTIES.keys)

        expected_csv = [
          "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived,Custom Property: boolean,Custom Property: multi-select,Custom Property: single-select,Custom Property: text",
          "org-name/repo-name,1,CodeQL,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,ABCD,,,private,,false,true,\"[\"\"apples\"\",\"\"bananas\"\"]\",onions,some-text",
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      private

      def generate_fake_data(
        number_of_alerts: 1,
        teams: %w[team-1 a-team-2 b-team-with,comma],
        properties: DEFAULT_PROPERTIES,
        topics: %w[topic-1 a-topic-2]
      )
        fake_data = []
        number_of_alerts.times do |i|
          row = {}

          row["repository_nwo"] = "org-name/repo-name"
          row["repository_id"] = 1
          row["tool"] = "CodeQL"
          row["alert_number"] = i + 1
          row["alert_severity"] = "critical"
          row["alert_created_at"] = "2023"
          row["alert_updated_at"] = "2024"
          row["alert_resolved_at"] = nil
          row["alert_reopened_at"] = nil
          row["alert_resolution"] = nil
          row["alert_bypassed"] = false
          row["alert_type"] = "alert-type"
          row["alert_type_provider"] = "alert-type-provider"
          row["alert_validity"] = "active"
          row["ghsa_id"] = "1234"
          row["ecosystem"] = "ecosystem"
          row["package_name"] = "package"
          row["dependency_scope"] = "scope"
          row["rule_sarif_identifier"] = "ABCD"
          row["codeql_tool"] = "ABCD"
          row["third_party_tool"] = nil
          row["teams"] = teams
          row["visibility"] = "private"
          row["repo_topics"] = topics
          row["archived"] = false
          row["repo_properties"] = properties&.with_indifferent_access

          fake_data << row
        end
        fake_data
      end
    end
  end
end
