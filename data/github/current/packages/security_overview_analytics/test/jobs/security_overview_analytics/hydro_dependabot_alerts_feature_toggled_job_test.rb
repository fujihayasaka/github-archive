# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroDependabotAlertsFeatureToggledJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @queue = HydroDependabotAlertsFeatureToggledJob.queue_name
      @schema = "github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent"
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(true)
      @utc_now = Time.current.utc
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@utc_now)
    end

    context "#perform" do
      test "can create data on feature toggle event" do
        FeatureStatusRevision.destroy_all
        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

        assert_query_counts(6) do
          perform_hydro_message_job({
            repository_id: @repo.id,
            action: "enable"
          }, schema: @schema, queue: @queue)
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        assert new_record&.dependabot_alerts_enabled
        refute new_record&.code_scanning_enabled
        refute new_record&.advanced_security_enabled
        refute new_record&.secret_scanning_enabled
        refute new_record&.secret_scanning_push_protection_enabled

        refute_dogstats_increment "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
      end

      test "does nothing if repository owner validation fails" do
        TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

        assert_query_counts(2) do
          perform_hydro_message_job({
            repository_id: @repo.id,
            action: "enable"
          }, schema: @schema, queue: @queue)
        end

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert_dogstats_increment 1, "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
      end

      test "does nothing if action is not 'enable' or 'disable'" do
        assert_query_counts(0) do
          assert_nothing_raised do
            perform_hydro_message_job({
              action: "digest_sent"
            }, schema: @schema, queue: @queue)
          end
        end

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert_dogstats_increment 1, "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
      end

      test "can create revision on new date" do
        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          date_id: @date_id - 1,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          dependabot_alerts_enabled: false
        )
        refute last_revision.dependabot_alerts_enabled

        Timecop.freeze(@utc_now) do
          assert_query_counts(8) do
            perform_hydro_message_job({
              repository_id: last_revision.repository_id,
              action: "enable"
            }, schema: @schema, queue: @queue)
          end
        end

        refute last_revision.reload.dependabot_alerts_enabled
        assert_equal @date_id - 1, last_revision.date_id
        assert_equal @date_id, last_revision.next_revision_date_id

        new_revision = FeatureStatusRevision.find_by(
          next_revision_date_id: Date::FUTURE_DATE_ID,
          repository_id: last_revision.repository_id
        )
        assert new_revision&.dependabot_alerts_enabled
        assert_equal @date_id, new_revision&.date_id
        assert_equal last_revision.code_scanning_enabled, new_revision&.code_scanning_enabled
        assert_equal last_revision.advanced_security_enabled, new_revision&.advanced_security_enabled
        assert_equal last_revision.secret_scanning_enabled, new_revision&.secret_scanning_enabled
        assert_equal last_revision.secret_scanning_push_protection_enabled, new_revision&.secret_scanning_push_protection_enabled

        refute_dogstats_increment "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
      end

      test "can update revision on the same date" do
        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          date_id: @date_id,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          repository_id: @repo.id,
          dependabot_alerts_enabled: false,
          advanced_security_enabled: true,
          secret_scanning_enabled: true,
          secret_scanning_push_protection_enabled: true,
          code_scanning_enabled: true
        )
        refute last_revision.dependabot_alerts_enabled
        assert last_revision.code_scanning_enabled
        assert last_revision.advanced_security_enabled
        assert last_revision.secret_scanning_enabled
        assert last_revision.secret_scanning_push_protection_enabled

        Timecop.freeze(@utc_now) do
          assert_query_counts(7) do
            perform_hydro_message_job({
              repository_id: last_revision.repository_id,
              action: "enable"
            }, schema: @schema, queue: @queue)
          end
        end

        assert last_revision.reload.dependabot_alerts_enabled
        assert last_revision.code_scanning_enabled
        assert last_revision.advanced_security_enabled
        assert last_revision.secret_scanning_enabled
        assert last_revision.secret_scanning_push_protection_enabled
        assert_equal @date_id, last_revision.date_id
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, last_revision.next_revision_date_id

        refute_dogstats_increment "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
      end

      test "enqueues backfill job if feature enabled" do
        Initialization::Repositories::DependabotAlertsJob.expects(:perform_later).once

        message = {
          repository_id: @repo.id,
          action: "enable"
        }
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      test "does not enqueue backfill job if feature disabled" do
        Initialization::Repositories::DependabotAlertsJob.expects(:perform_later).never

        message = {
          repository_id: @repo.id,
          action: "disable"
        }
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
