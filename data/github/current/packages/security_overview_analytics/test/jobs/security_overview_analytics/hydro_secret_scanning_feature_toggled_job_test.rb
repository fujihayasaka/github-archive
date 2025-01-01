# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroSecretScanningFeatureToggledJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @queue = HydroSecretScanningFeatureToggledJob.queue_name
      @schema = "github.secret_scanning.v1.SecretScanningFeatureToggled"
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
            feature_enabled: true
          }, schema: @schema, queue: @queue)
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        refute new_record&.code_scanning_enabled
        refute new_record&.dependabot_alerts_enabled
        refute new_record&.advanced_security_enabled
        assert new_record&.secret_scanning_enabled
        refute new_record&.secret_scanning_push_protection_enabled

        refute_dogstats_increment "security_overview_analytics.event.secret_scanning_feature_toggled.skipped"
      end

      test "does nothing if repository owner validation fails" do
        FeatureStatusRevision.destroy_all
        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

        assert_query_counts(2) do
          perform_hydro_message_job({
            repository_id: @repo.id,
            feature_enabled: true
          }, schema: @schema, queue: @queue)
        end

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert_dogstats_increment 1, "security_overview_analytics.event.secret_scanning_feature_toggled.skipped"
      end

      test "can create revision on new date" do
        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          date_id: @date_id - 1,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          secret_scanning_enabled: false
        )
        refute last_revision.secret_scanning_enabled

        Timecop.freeze(@utc_now) do
          assert_query_counts(8) do
            perform_hydro_message_job({
              repository_id: last_revision.repository_id,
              feature_enabled: true
            }, schema: @schema, queue: @queue)
          end
        end

        refute last_revision.reload.secret_scanning_enabled
        assert_equal @date_id - 1, last_revision.date_id
        assert_equal @date_id, last_revision.next_revision_date_id

        new_revision = FeatureStatusRevision.find_by(
          next_revision_date_id: Date::FUTURE_DATE_ID,
          repository_id: last_revision.repository_id
        )
        assert new_revision&.secret_scanning_enabled
        assert_equal @date_id, new_revision&.date_id
        assert_equal last_revision.dependabot_alerts_enabled, new_revision&.dependabot_alerts_enabled
        assert_equal last_revision.advanced_security_enabled, new_revision&.advanced_security_enabled
        assert_equal last_revision.secret_scanning_push_protection_enabled, new_revision&.secret_scanning_push_protection_enabled
        assert_equal last_revision.code_scanning_enabled, new_revision&.code_scanning_enabled

        refute_dogstats_increment "security_overview_analytics.event.secret_scanning_feature_toggled.skipped"
      end

      test "can update revision on the same date" do
        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          date_id: @date_id,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          dependabot_alerts_enabled: true,
          advanced_security_enabled: true,
          secret_scanning_enabled: false,
          secret_scanning_push_protection_enabled: true,
          code_scanning_enabled: true
        )
        assert last_revision.dependabot_alerts_enabled
        assert last_revision.advanced_security_enabled
        refute last_revision.secret_scanning_enabled
        assert last_revision.secret_scanning_push_protection_enabled
        assert last_revision.code_scanning_enabled

        Timecop.freeze(@utc_now) do
          assert_query_counts(7) do
            perform_hydro_message_job({
              repository_id: last_revision.repository_id,
              feature_enabled: true
            }, schema: @schema, queue: @queue)
          end
        end

        assert last_revision.reload.dependabot_alerts_enabled
        assert last_revision.advanced_security_enabled
        assert last_revision.secret_scanning_enabled
        assert last_revision.secret_scanning_push_protection_enabled
        assert last_revision.code_scanning_enabled
        assert_equal @date_id, last_revision.date_id
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, last_revision.next_revision_date_id

        refute_dogstats_increment "security_overview_analytics.event.secret_scanning_feature_toggled.skipped"
      end

      test "enqueues backfill job if feature enabled" do
        Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).once

        message = {
          repository_id: @repo.id,
          feature_enabled: true
        }
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      test "does not enqueue backfill job if feature disabled" do
        Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).never

        message = {
          repository_id: @repo.id,
          feature_enabled: false
        }
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      test "marks 'business' plans orgs as eligible if feature is toggled on private repo", skip_enterprise: true, skip_in_multitenant_mode: true do
        org = create(:organization, plan: "business")
        repo = create(:private_repository, owner: org)

        # Marking tenant validation to fail to simplify test
        TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

        # A lot more queries to determine eligibility + apply tracking information if so
        assert_query_counts(10) do
          perform_hydro_message_job({
            repository_id: repo.id,
            feature_enabled: true
          }, schema: @schema, queue: @queue)
        end

        assert ::Repository::SecurityCenterBusinessPlanOrgEligibility.new.enabled?(org.reload)
      end
    end
  end
end
