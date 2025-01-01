# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      class ExportCsvGeneratorTest < GitHub::TestCase
        include SecurityCenter::TestFixtures
        include ::SecurityOverviewAnalytics::TestFixtures

        context "#generate" do
          test "it works" do
            data = Queries::DataExportQuery::Result.new(
              items: [
                new_list_item,
              ]
            )

            actual = ExportCsvGenerator.generate(data)

            expected = [
              ExportCsvGenerator::HEADERS.join(","),
              "org/repo,1,42,https://github.com/org/repo/pulls/42,2,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,"
            ].join("\n") + "\n"
            assert_equal expected, actual
          end

          test "it includes repository teams" do
            data = Queries::DataExportQuery::Result.new(
              items: [
                new_list_item(
                  alert_number: 1,
                  repository_teams: %w[users staff],
                ),
                new_list_item(
                  alert_number: 2,
                  repository_teams: %w[admins],
                ),
                new_list_item(
                  alert_number: 3,
                  repository_teams: [],
                ),
              ]
            )

            actual = ExportCsvGenerator.generate(data)

            expected = [
              ExportCsvGenerator::HEADERS.join(","),
              "org/repo,1,42,https://github.com/org/repo/pulls/42,1,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,\"[\"\"staff\"\",\"\"users\"\"]\",",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,2,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,\"[\"\"admins\"\"]\",",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,3,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,",
            ].join("\n") + "\n"
            assert_equal expected, actual
          end

          test "it includes repository topics" do
            data = Queries::DataExportQuery::Result.new(
              items: [
                new_list_item(
                  alert_number: 1,
                  repository_topics: %w[apple grape banana],
                ),
                new_list_item(
                  alert_number: 2,
                  repository_topics: %w[pear banana],
                ),
                new_list_item(
                  alert_number: 3,
                  repository_topics: %w[watermelon],
                ),
              ]
            )

            actual = ExportCsvGenerator.generate(data)

            expected = [
              ExportCsvGenerator::HEADERS.join(","),
              "org/repo,1,42,https://github.com/org/repo/pulls/42,1,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,\"[\"\"apple\"\",\"\"banana\"\",\"\"grape\"\"]\"",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,2,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,\"[\"\"banana\"\",\"\"pear\"\"]\"",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,3,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,\"[\"\"watermelon\"\"]\"",
            ].join("\n") + "\n"
            assert_equal expected, actual
          end

          test "it includes repository custom properties" do
            data = Queries::DataExportQuery::Result.new(
              items: [
                new_list_item(
                  alert_number: 1,
                  repository_properties: {
                    "single-select" => nil,
                    "multi-select" => %w[one two],
                    "boolean" => nil,
                    "string" => "woof",
                  }
                ),
                new_list_item(
                  alert_number: 2,
                  repository_properties: {
                    "single-select" => "foo",
                    "multi-select" => nil,
                    "boolean" => "true",
                    "string" => nil,
                  }
                ),
              ]
            )

            actual = ExportCsvGenerator.generate(data)

            expected = [
              "#{ExportCsvGenerator::HEADERS.join(",")},Custom Property: boolean,Custom Property: multi-select,Custom Property: single-select,Custom Property: string",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,1,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,,,\"[\"\"one\"\",\"\"two\"\"]\",,woof",
              "org/repo,1,42,https://github.com/org/repo/pulls/42,2,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,,true,,foo,",
            ].join("\n") + "\n"
            assert_equal expected, actual
          end

          context "when query results is empty" do
            test "it does not write data rows" do
              data = Queries::DataExportQuery::Result.new(
                items: []
              )

              actual = ExportCsvGenerator.generate(data)

              expected = [
                ExportCsvGenerator::HEADERS.join(","),
              ].join("\n") + "\n"
              assert_equal expected, actual
            end
          end

          context "when write_headers is false" do
            test "it does not write header row" do
              data = Queries::DataExportQuery::Result.new(
                items: [
                  new_list_item,
                ]
              )

              actual = ExportCsvGenerator.generate(data, false)

              expected = [
                "org/repo,1,42,https://github.com/org/repo/pulls/42,2,Critical,java/xss,2024-08-01 00:00:00 -0700,2024-08-01 00:00:00 -0700,,,false,false,private,false,,"
              ].join("\n") + "\n"
              assert_equal expected, actual
            end
          end
        end

        private

        def new_list_item(kwargs = {})
          Queries::DataExportQuery::ListItem.new(
            **T.unsafe({
              repository_id: 1,
              repository_nwo: "org/repo",
              pull_request_id: 1,
              pull_request_number: 42,
              pull_request_url: "https://github.com/org/repo/pulls/42",
              alert_number: 2,
              severity: "Critical",
              rule_sarif_identifier: "java/xss",
              created_at: Time.new(2024, 8, 1),
              updated_at: Time.new(2024, 8, 1),
              resolved_at: nil,
              resolved_reason: nil,
              has_autofix: false,
              autofix_accepted: false,
              repository_visibility: "private",
              repository_archived: false,
              repository_teams: [],
              repository_topics: [],
              repository_properties: {},
              **kwargs
            }),
          )
        end
      end
    end
  end
end
