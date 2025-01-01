# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroCodeScanningFeatureToggledJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    QUEUE = HydroCodeScanningFeatureToggledJob.queue_name
    SCHEMAS = [
      "code_scanning.v0.CodeScanningFeatureToggled",
      "github.code_security.v1.CodeSecurityFeatureToggled"
    ]

    fixtures do
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(true)
      @utc_now = Time.current.utc
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@utc_now)
    end

    SCHEMAS.each do |schema|
      context "#{schema}" do
        context "#perform" do
          test "can create data on feature toggle event" do
            FeatureStatusRevision.destroy_all
            refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

            assert_query_counts(6) do
              perform_hydro_message_job({
                repository_id: @repo.id,
                feature_enabled: true
              }, schema: schema, queue: QUEUE)
            end

            new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
            assert new_record
            assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
            assert new_record&.code_scanning_enabled
            refute new_record&.dependabot_alerts_enabled
            refute new_record&.advanced_security_enabled
            refute new_record&.secret_scanning_enabled
            refute new_record&.secret_scanning_push_protection_enabled

            refute_dogstats_increment "security_overview_analytics.event.code_scanning_feature_toggled.skipped"
          end

          test "does nothing if repository owner validation fails" do
            TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

            assert_query_counts(2) do
              perform_hydro_message_job({
                repository_id: @repo.id,
                feature_enabled: true
              }, schema: schema, queue: QUEUE)
            end

            refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
            assert_dogstats_increment 1, "security_overview_analytics.event.code_scanning_feature_toggled.skipped"
          end

          test "can create revision on new date" do
            last_revision = create(
              :security_overview_analytics_feature_status_revision,
              date_id: @date_id - 1,
              next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
              code_scanning_enabled: false
            )
            refute last_revision.code_scanning_enabled

            Timecop.freeze(@utc_now) do
              assert_query_counts(8) do
                perform_hydro_message_job({
                  repository_id: last_revision.repository_id,
                  feature_enabled: true
                }, schema: schema, queue: QUEUE)
              end
            end

            refute last_revision.reload.code_scanning_enabled
            assert_equal @date_id - 1, last_revision.date_id
            assert_equal @date_id, last_revision.next_revision_date_id

            new_revision = FeatureStatusRevision.find_by(
              next_revision_date_id: Date::FUTURE_DATE_ID,
              repository_id: last_revision.repository_id
            )
            assert new_revision&.code_scanning_enabled
            assert_equal @date_id, new_revision&.date_id
            assert_equal last_revision.dependabot_alerts_enabled, new_revision&.dependabot_alerts_enabled
            assert_equal last_revision.advanced_security_enabled, new_revision&.advanced_security_enabled
            assert_equal last_revision.secret_scanning_enabled, new_revision&.secret_scanning_enabled
            assert_equal last_revision.secret_scanning_push_protection_enabled, new_revision&.secret_scanning_push_protection_enabled

            refute_dogstats_increment "security_overview_analytics.event.code_scanning_feature_toggled.skipped"
          end

          test "can update revision on the same date" do
            last_revision = create(
              :security_overview_analytics_feature_status_revision,
              date_id: @date_id,
              next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
              dependabot_alerts_enabled: true,
              advanced_security_enabled: true,
              secret_scanning_enabled: true,
              secret_scanning_push_protection_enabled: true,
              code_scanning_enabled: false
            )
            refute last_revision.code_scanning_enabled
            assert last_revision.dependabot_alerts_enabled
            assert last_revision.advanced_security_enabled
            assert last_revision.secret_scanning_enabled
            assert last_revision.secret_scanning_push_protection_enabled

            Timecop.freeze(@utc_now) do
              assert_query_counts(7) do
                perform_hydro_message_job({
                  repository_id: last_revision.repository_id,
                  feature_enabled: true
                }, schema: schema, queue: QUEUE)
              end
            end

            assert last_revision.reload.code_scanning_enabled
            assert last_revision.dependabot_alerts_enabled
            assert last_revision.advanced_security_enabled
            assert last_revision.secret_scanning_enabled
            assert last_revision.secret_scanning_push_protection_enabled
            assert_equal @date_id, last_revision.date_id
            assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, last_revision.next_revision_date_id

            refute_dogstats_increment "security_overview_analytics.event.code_scanning_feature_toggled.skipped"
          end

          test "enqueues backfill job if feature enabled" do
            Initialization::Repositories::CodeScanningAlertsJob.expects(:perform_later).once
            Fanout::Initialization::CodeScanningPullRequestAlertsJob.expects(:perform_later).once

            message = {
              repository_id: @repo.id,
              feature_enabled: true
            }
            perform_hydro_message_job(message, schema: schema, queue: QUEUE)
          end

          test "does not enqueue backfill job if feature disabled" do
            Initialization::Repositories::CodeScanningAlertsJob.expects(:perform_later).never
            Fanout::Initialization::CodeScanningPullRequestAlertsJob.expects(:perform_later).never

            message = {
              repository_id: @repo.id,
              feature_enabled: false
            }
            perform_hydro_message_job(message, schema: schema, queue: QUEUE)
          end

          test "marks 'business' plans orgs as eligible if feature is toggled on private repo", skip_enterprise: true, skip_in_multitenant_mode: true do
            org = create(:organization, plan: "business")
            repo = create(:private_repository, owner: org)
            refute ::Repository::SecurityCenterBusinessPlanOrgEligibility.new.enabled?(org.reload)

            # Marking tenant validation to fail to simplify test
            TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

            # A lot more queries to determine eligibility + apply tracking information if so
            assert_query_counts(10) do
              perform_hydro_message_job({
                repository_id: repo.id,
                feature_enabled: true
              }, schema: schema, queue: QUEUE)
            end

            assert ::Repository::SecurityCenterBusinessPlanOrgEligibility.new.enabled?(org.reload)
          end
        end
      end
    end
  end
end
