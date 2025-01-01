# typed: true
# frozen_string_literal: true

require_relative "date_test_helpers"

module SecurityOverviewAnalytics
  module Test
    module TestHelpers
      module AlertTrendsTestHelpers
        extend T::Helpers
        extend ActiveSupport::Concern
        include ::SecurityOverviewAnalytics::Test::TestHelpers::DateTestHelpers

        requires_ancestor { ActiveSupport::TestCase }

        THIRD_PARTY_TOOL_1 = "third-party-1"
        THIRD_PARTY_TOOL_2 = "third Party 2"
        THIRD_PARTY_TOOL_3 = "ThIrD PaRtY 3"
        THIRD_PARTY_TOOL_4 = "ThIrD PaRtY 4"
        THIRD_PARTY_TOOLS = [
          THIRD_PARTY_TOOL_1,
          THIRD_PARTY_TOOL_2,
          THIRD_PARTY_TOOL_3,
          THIRD_PARTY_TOOL_4
        ]

        sig { void }
        def create_fixtures
          @biz = create(:business)
          @org_admin = create(:user)
          @user_session = create(:user_session, user: @org_admin)
          @org = create(:organization, business: @biz, admin: @org_admin)
          @repo = create(:private_repository, owner: @org)
          @soa_repo = create(:soa_repository, repository: @repo)
          create(
            :security_overview_analytics_feature_status_revision,
            repository_metadata: @soa_repo,
            date_id: 20220101,
            dependabot_alerts_enabled: true,
            code_scanning_enabled: true,
            secret_scanning_enabled: true,
            secret_scanning_push_protection_enabled: true,
            advanced_security_enabled: true
          )

          @fake_today = ::Date.new(2023, 10, 10).freeze
          create_date_entries(from_date: ::Date.new(2022, 1, 1), to_date: ::Date.new(2023, 12, 31))
          create_alerts_for_tools
        end

        sig { void }
        def create_alerts_for_tools
          idx = 0
          datetime_sequence = generate_datetime_sequence

          # Dependabot
          date = @fake_today - 100.days
          create(:soa_dependabot_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), ecosystem: "npm", updated_at: datetime_sequence[0])
          date = @fake_today - 3.days
          create(:soa_dependabot_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), ecosystem: "npm", updated_at: datetime_sequence[1])
          date = @fake_today - 1.day
          create(:soa_dependabot_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), ecosystem: "npm", updated_at: datetime_sequence[2])

          # Secret scanning
          date = @fake_today - 3.days
          create(:soa_secret_scanning_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), updated_at: datetime_sequence[3])
          date = @fake_today - 2.days
          create(:soa_secret_scanning_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), updated_at: datetime_sequence[4])
          date = @fake_today - 1.day
          create(:soa_secret_scanning_alert_revision, alert_number: idx += 1, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), updated_at: datetime_sequence[5])

          # CodeQL
          date = @fake_today - 7.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: "CodeQL", rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[6])
          date = @fake_today - 5.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: "CodeQL", rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[7])
          date = @fake_today - 2.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: "CodeQL", rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[8])

          # Third-party tools 1, 3, and 4 are the top 3 tools by alert count.

          # Third-party tool 1
          date = @fake_today - 50.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_1, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[9])
          date = @fake_today - 40.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_1, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[10])

          # Third-party tool 2
          date = @fake_today - 30.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_2, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[11])

          # Third-party tool 3
          date = @fake_today - 20.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_3, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[12])
          date = @fake_today - 15.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_3, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[13])

          # Third-party tool 4
          date = @fake_today - 10.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_4, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[14])
          date = @fake_today - 5.days
          create(:soa_code_scanning_alert_revision, alert_number: idx += 1, alert_id: idx, repository: @repo, alert_created_at: date, alert_resolved_at: date, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(date), tool: THIRD_PARTY_TOOL_4, rule_sarif_identifier: "some-rule", updated_at: datetime_sequence[15])
        end

        sig { returns(T::Array[Time]) }
        def generate_datetime_sequence
          # Set up sequence of datetimes that are spaced 1 second apart to test slicing
          # of the alert revisions by date
          now = Time.now
          (1..100).map do |i|
            (now + i.seconds).freeze
          end.freeze
        end
      end
    end
  end
end
