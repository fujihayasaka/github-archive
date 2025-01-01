# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroDependabotSecurityUpdatesFeatureToggledJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    # In production these include the `hydro.` prefix, while in tests/dev they do not. Assert both.
    ENABLED_SCHEMAS = [
      "github.v1.RepositoryDependencyUpdatesVulnerabilitiesEnabled",
      "hydro.schemas.github.v1.RepositoryDependencyUpdatesVulnerabilitiesEnabled",
    ].freeze

    DISABLED_SCHEMAS = [
      "github.v1.RepositoryDependencyUpdatesVulnerabilitiesDisabled",
      "hydro.schemas.github.v1.RepositoryDependencyUpdatesVulnerabilitiesDisabled",
    ].freeze

    fixtures do
      @queue = HydroDependabotSecurityUpdatesFeatureToggledJob.queue_name
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(true)
      @utc_now = Time.current.utc
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@utc_now)
    end

    (ENABLED_SCHEMAS + DISABLED_SCHEMAS).each do |schema|
      context "when schema is #{schema}" do
        context "#perform" do
          test "can create data on feature toggle event" do
            FeatureStatusRevision.destroy_all
            refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

            assert_query_counts(11) do
              perform_hydro_message_job({
                repository: { id: @repo.id },
              }, schema: schema, queue: @queue)
            end

            new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
            assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id

            assert_equal enabled_event?(schema), new_record&.dependabot_security_updates_enabled

            refute_dogstats_increment "security_overview_analytics.event.dependabot_security_updates_feature_toggled.skipped"
          end

          test "does nothing if repository owner validation fails" do
            TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

            assert_query_counts(1) do
              perform_hydro_message_job({
                repository: { id: @repo.id },
              }, schema: schema, queue: @queue)
            end

            refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
            assert_dogstats_increment 1, "security_overview_analytics.event.dependabot_security_updates_feature_toggled.skipped", tags: ["reason:ineligible_owner"]
          end

          test "can create revision on new date" do
            last_revision = create(
              :security_overview_analytics_feature_status_revision,
              date_id: @date_id - 1,
              next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
              dependabot_security_updates_enabled: !enabled_event?(schema),
            )
            assert_equal !enabled_event?(schema), last_revision.dependabot_security_updates_enabled

            Timecop.freeze(@utc_now) do
              assert_query_counts(18) do
                perform_hydro_message_job({
                  repository: { id: last_revision.repository_id },
                }, schema: schema, queue: @queue)
              end
            end

            # confirm we didn't change the previous day's revision
            last_revision.reload
            assert_equal !enabled_event?(schema), last_revision.dependabot_security_updates_enabled
            assert_equal @date_id - 1, last_revision.date_id
            assert_equal @date_id, last_revision.next_revision_date_id

            new_revision = FeatureStatusRevision.find_by(
              next_revision_date_id: Date::FUTURE_DATE_ID,
              repository_id: last_revision.repository_id
            )
            assert_equal enabled_event?(schema), new_revision&.dependabot_security_updates_enabled
            assert_equal @date_id, new_revision&.date_id
            # all other statuses carried from previous day's revision
            assert_equal last_revision.dependabot_alerts_enabled, new_revision&.dependabot_alerts_enabled
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
              dependabot_security_updates_enabled: !enabled_event?(schema),
              advanced_security_enabled: false,
              secret_scanning_enabled: false,
              secret_scanning_push_protection_enabled: false,
              code_scanning_enabled: false
            )
            refute last_revision.dependabot_alerts_enabled
            assert_equal !enabled_event?(schema), last_revision.dependabot_security_updates_enabled
            refute last_revision.code_scanning_enabled
            refute last_revision.advanced_security_enabled
            refute last_revision.secret_scanning_enabled
            refute last_revision.secret_scanning_push_protection_enabled

            Timecop.freeze(@utc_now) do
              assert_query_counts(14) do
                perform_hydro_message_job({
                  repository: { id: @repo.id },
                }, schema: schema, queue: @queue)
              end
            end

            last_revision.reload
            refute last_revision.dependabot_alerts_enabled
            assert_equal enabled_event?(schema), last_revision.dependabot_security_updates_enabled
            refute last_revision.code_scanning_enabled
            refute last_revision.advanced_security_enabled
            refute last_revision.secret_scanning_enabled
            refute last_revision.secret_scanning_push_protection_enabled
            assert_equal @date_id, last_revision.date_id
            assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, last_revision.next_revision_date_id

            refute_dogstats_increment "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped"
          end
        end

        context "#deviation reporting" do
          test "logs deviation and revision age to datadog when flag is on" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:incremental_deviation_reporting_enabled?).returns(true)
            SecurityProduct::VulnerabilityUpdates.any_instance.stubs(:enabled?).returns(!enabled_event?(schema))

            last_revision = create(
              :security_overview_analytics_feature_status_revision,
              next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
            )

            message = {
              repository: { id: last_revision.repository_id }
            }
            perform_hydro_message_job(message, schema: schema, queue: @queue)

            assert_dogstats_increment 1, "security_overview_analytics.feature_status.origin_deviation", tags: ["feature:dependabot_security_updates_enabled"]
            assert_dogstats_distribution 1, "security_overview_analytics.feature_status.origin_deviation.previous_revision_seconds_ago.dist"
          end
        end
      end
    end

    private

    def enabled_event?(schema)
      ENABLED_SCHEMAS.include?(schema)
    end
  end
end
