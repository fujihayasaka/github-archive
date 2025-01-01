# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module OverviewDashboard
    class CsvGeneratorTest < GitHub::TestCase
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

      test "works end-to-end" do
        user = create(:user)
        org = create(:organization, admin: user)
        repo = create(:private_repository, owner: org)
        team = create(:team, organization: org)
        repo.send(:grant, team, :admin)

        definition = create :custom_property_definition, :single_select, source: org, property_name: "single-select", allowed_values: %w[value another nomatch]
        create :custom_property_value, target: repo, definition: definition, value: "value"

        topic = create(:topic, name: "repo-topic")
        topic.repository_topics.create!(repository: repo, state: :created, user: user)

        now = Time.now

        metadata = create(:soa_repository, repository: repo)
        soa_date = create(:soa_date, date_value: now)
        create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: metadata, date: soa_date)
        create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: soa_date, alert_created_at: now - 2.days, alert_updated_at: now - 1.day, alert_resolved_at: now, alert_resolution: 37)
        create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: soa_date, alert_created_at: now - 2.days, alert_updated_at: now - 1.day, alert_resolved_at: now, alert_resolution: 3)
        create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: soa_date, alert_created_at: now - 2.days, alert_updated_at: now - 1.day, alert_resolved_at: now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed867", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb47")

        # query data and generate CSV:

        ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
          .any_instance.stubs(:selected_backend_security_features)
          .returns(%w[dependabot_alerts secret_scanning codeql])

        csv = ExportCsvGenerator.generate(SecurityOverviewAnalytics::Dashboards::Overview::Queries::ExportData.for_organization(
          organization: org,
          user:,
          query: Search::Queries::SecurityCenter::QueryParser.new(""),
          start_date: now.to_date - 7.days,
          end_date: now.to_date,
          user_session: create(:user_session, user: user),
          return_alert_count: true,
          is_open_selected: true,
        ).perform)

        expected_csv = [
          BASE_HEADERS.join(",") + ",Custom Property: single-select",
          "#{repo.name},#{repo.id},CodeQL,1,critical,#{now - 2.days},#{now - 1.day},#{now},,risk_accepted,,,,,,,,,rb/unsafe-deserialization,,\"[\"\"#{team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value",
          "#{repo.name},#{repo.id},dependabot,1,low,#{now - 2.days},#{now - 1.day},#{now},,auto_dismissed,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value",
          "#{repo.name},#{repo.id},secret-scanning,1,critical,#{now - 2.days},#{now - 1.day},#{now},,false_positive,false,ddd3b186-0925-4c5b-bf1a-1f0ca57ed867,86f85cc1-8424-46bf-b196-46e7ffa7eb47,unknown,,,,,,,\"[\"\"#{team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value",
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "formats data correctly" do
        csv = ExportCsvGenerator.generate(generate_fake_data(number_of_alerts: 5))

        expected_csv = [
          (BASE_HEADERS + DEFAULT_PROPERTIES.keys.sort.map { |key| "Custom Property: #{key}" }).join(","),
          "repo-name,1,dependabot,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "repo-name,1,dependabot,2,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "repo-name,1,dependabot,3,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "repo-name,1,dependabot,4,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text",
          "repo-name,1,dependabot,5,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\",\"\"team-1\"\"]\",private,\"[\"\"a-topic-2\"\",\"\"topic-1\"\"]\",false,true,\"[\"\"apples\"\",\"\"bananas\"\",\"\"pears\"\"]\",onions,some-text"
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "handles nil data" do
        csv = ExportCsvGenerator.generate(generate_fake_data(teams: nil, properties: nil, topics: nil))

        expected_csv = [
          BASE_HEADERS.join(","),
          "repo-name,1,dependabot,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,,private,,false"
        ].join("\n") + "\n"

        assert_equal expected_csv, csv
      end

      test "limits number of teams per repo" do
        ExportCsvGenerator.stub_const(:ELEMENT_COUNT_CAP, 2) do
          csv = ExportCsvGenerator.generate(generate_fake_data(properties: nil, topics: nil))

          expected_csv = [
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 2 values),Repository Visibility,Repository Topics,Repository Archived",
            "repo-name,1,dependabot,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,\"[\"\"a-team-2\"\",\"\"b-team-with,comma\"\"]\",private,,false",
          ].join("\n") + "\n"

          assert_equal expected_csv, csv
        end
      end

      test "limits number of property multiselect elements per repo" do
        ExportCsvGenerator.stub_const(:ELEMENT_COUNT_CAP, 2) do
          csv = ExportCsvGenerator.generate(generate_fake_data(teams: nil, topics: nil, properties: { "multi-select": %w[apples pears bananas] }))

          expected_csv = [
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 2 values),Repository Visibility,Repository Topics,Repository Archived,Custom Property: multi-select",
            "repo-name,1,dependabot,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,active,1234,ecosystem,package,scope,,ABCD,,private,,false,\"[\"\"apples\"\",\"\"bananas\"\"]\"",
          ].join("\n") + "\n"

          assert_equal expected_csv, csv
        end
      end

      test "validity of 5 is mapped to unknown" do
        data = generate_fake_data(teams: nil, topics: nil, properties: nil)
        data.first["alert_validity"] = 5
        csv = ExportCsvGenerator.generate(data)

        expected_csv = [
          "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived",
          "repo-name,1,dependabot,1,critical,2023,2024,,,,false,alert-type,alert-type-provider,unknown,1234,ecosystem,package,scope,,ABCD,,private,,false",
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

          row["name"] = "repo-name"
          row["repository_id"] = 1
          row["tool"] = "dependabot"
          row["alert_number"] = i + 1
          row["alert_severity"] = "critical"
          row["alert_created_at"] = "2023"
          row["alert_updated_at"] = "2024"
          row["alert_resolved_at"] = nil
          row["alert_reopened_at"] = nil
          row["alert_resolution"] = nil
          row["alert_bypassed"] = 0
          row["alert_type"] = "alert-type"
          row["alert_type_provider"] = "alert-type-provider"
          row["alert_validity"] = 1
          row["ghsa_id"] = "1234"
          row["ecosystem"] = "ecosystem"
          row["package_name"] = "package"
          row["dependency_scope"] = "scope"
          row["rule_sarif_identifier"] = "ABCD"
          row["teams"] = teams
          row["visibility"] = 1
          row["repo_topics"] = topics
          row["archived"] = 0
          row["repo_properties"] = properties

          fake_data << row
        end
        fake_data
      end
    end
  end
end
