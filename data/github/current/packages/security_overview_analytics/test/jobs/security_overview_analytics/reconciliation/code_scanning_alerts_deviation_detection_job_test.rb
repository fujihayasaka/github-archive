# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  module Reconciliation
    class CodeScanningAlertsDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)
        @repo = create(:repository, owner: @org, name: "foo")
        @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).returns(true)
        GitHub.logger.stubs(:info).returns(true)
        # Stub session to imitate a locked session, otherwise tests would bail the after_perform block because
        # session_started_at and last_session_started_at are both nil.
        Session.any_instance.stubs(:session_started_at).returns(Time.now.utc)
        @stats_tags = ["metric_type:code_scanning_alerts"].compact

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
        end
        FeatureFlagHelper.stubs(:code_scanning_reconciliation_dry_run_mode?).returns(false)
      end

      context "#perform" do
        test "queues PostReconciliationRepoDeviationCountsJob", skip_enterprise: true do
          ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                alerts: []
              )
            ))

          Timecop.freeze do
            assert_enqueued_with(
              job: PostReconciliationRepoDeviationCountsJob,
              at: 1.hour.from_now,
            ) do
              assert_performed_jobs 1, only: CodeScanningAlertsDeviationDetectionJob do
                CodeScanningAlertsDeviationDetectionJob.perform_later(
                  repository_id: @repo.id,
                  session_id: "foo"
                )
              end
            end
          end
        end

        test "does not queue PostReconciliationRepoDeviationCountsJob in GHES", enterprise_only: true do
          Timecop.freeze do
            assert_no_performed_jobs only: PostReconciliationRepoDeviationCountsJob do
              CodeScanningAlertsDeviationDetectionJob.perform_later(
                repository_id: @repo.id,
                session_id: "foo"
              )
            end
          end
        end

        context "when analytics doesn't have a latest revision for the alert" do
          test "it enqueues the alert upsert job" do
            # no revisions
            CodeScanningAlertRevision.delete_all

            # mock return of a single alert
            event_time = Time.now.utc
            alert = ::Turboscan::Proto::InsightsAlert.new(
              id: 1,
              repository_id: @repo.id,
              created_at: event_time - 3.days,
              updated_at: event_time,
              resolution: nil,
            )
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [alert]
                )
              ))

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

            assert_enqueued_jobs(1, only: CodeScanningAlertRevisionIngestionJob)
            assert_dogstats_increment("security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"])
          end

          context "#next_batch_offset_item_id" do
            test "returns the max alert id as the next offset item id" do
              event_time = ::Date.new(2023, 10, 2).to_time.utc
              alert1 = ::Turboscan::Proto::InsightsAlert.new(
                id: 101,
                number: 1,
                repository_id: @repo.id,
                created_at: event_time - 3.days,
                updated_at: event_time,
                resolution: nil,
              )
              alert2 = ::Turboscan::Proto::InsightsAlert.new(
                id: 201,
                number: 2,
                repository_id: @repo.id,
                created_at: event_time - 3.days,
                updated_at: event_time,
                resolution: nil,
              )
              alerts = [alert1, alert2]

              assert_equal 201, CodeScanningAlertsDeviationDetectionJob.new(repository_id: @repo.id).next_batch_offset_item_id(alerts).first
            end
          end

          test "queries latest revision by alert_id " do
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_id: 1, alert_number: 101, date_id: 20231002)
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_id: 3, alert_number: 1, date_id: 20231002)
            last_session_started_at = Time.current.utc - 7.days

            # Mock return of a single alert. This will return nil for existing revision because there is no alert_id 101.
            event_time = ::Date.new(2023, 10, 2).to_time.utc
            alert = ::Turboscan::Proto::InsightsAlert.new(
              id: 101,
              number: 1,
              repository_id: @repo.id,
              created_at: event_time - 3.days,
              updated_at: event_time,
              resolution: nil,
            )
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [alert]
                )
              ))

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo", last_session_started_at:)

            assert_enqueued_jobs(1, only: CodeScanningAlertRevisionIngestionJob)
            assert_dogstats_increment("security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"])
          end
        end

        context "when the alert has an older updated_at than the revision" do
          test "it does nothing" do
            event_time = Time.parse("2023-10-21 13:00:00 UTC")

            # a single "latest" revision
            rev = create(:soa_code_scanning_alert_revision,
              repository: @repo,
              alert_number: 1,
              date_id: Date.id_from_time(event_time),
              next_revision_date_id: Date::FUTURE_DATE_ID,
              alert_created_at: event_time - 2.days,
              alert_updated_at: event_time + 1.hour,
            )

            alert = ::Turboscan::Proto::InsightsAlert.new(
              id: rev.alert_number,
              repository_id: @repo.id,
              created_at: rev.alert_created_at.to_time,
              updated_at: event_time,
              resolution: nil,
            )
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [alert]
                )
              ))

            Session.any_instance.expects(:reset!).never

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

            assert_no_enqueued_jobs(only: CodeScanningAlertRevisionIngestionJob)
            assert_dogstats_increment("security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:old_source_alert_timestamp"])
          end
        end

        context "when the alert has deviations" do
          test "it enqueues the alert upsert job" do
            event_time = ::Date.new(2024, 9, 13).to_time.utc

            # a single "latest" revision
            rev = create(:soa_code_scanning_alert_revision,
              repository: @repo,
              alert_number: 1,
              alert_id: 2,
              date_id: Date.id_from_time(event_time),
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            alert = ::Turboscan::Proto::InsightsAlert.new(
              id: rev.alert_id,
              number: rev.alert_number,
              repository_id: @repo.id,
              created_at: rev.alert_created_at.to_time,
              updated_at: (rev.alert_updated_at + 1.hour).to_time,
            )
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [alert]
                )
              ))

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

            assert_enqueued_jobs(1, only: CodeScanningAlertRevisionIngestionJob)
            assert_dogstats_increment("security_overview_analytics.reconciliation.deviation",
              tags: @stats_tags + ["deviation:severity", "deviation:tool", "deviation:rule"])
          end
        end

        context "when the alert matches the latest revision" do
          test "it does nothing" do
            event_time = Time.now.utc
            rev = create(:soa_code_scanning_alert_revision,
              repository: @repo,
              alert_number: 1,
              date_id: Date.id_from_time(event_time),
              next_revision_date_id: Date::FUTURE_DATE_ID,
              alert_severity: "CRITICAL",
            )

            alert = ::Turboscan::Proto::InsightsAlert.new(
              repository_id: @repo.id,
              id: rev.alert_number,
              severity: rev.alert_severity&.upcase&.to_sym,
              tool_name: rev.tool,
              rule_sarif_identifier: rev.rule_sarif_identifier,
              created_at: rev.alert_created_at.to_time,
              updated_at: rev.alert_updated_at.to_time,
              closed: rev.alert_resolved,
              closed_at: rev.alert_resolved_at&.to_time,
              resolution: rev.alert_resolution,
            )
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [alert]
                )
              ))

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

            assert_no_enqueued_jobs(only: CodeScanningAlertRevisionIngestionJob)
            refute_dogstats_increment("security_overview_analytics.reconciliation.deviation")
          end
        end

        context "purging newer revisions" do
          context "when analytics has revisions dated after the logical alert" do
            test "it purges any extraneous revisions based on alert_id" do
              repository_id = @repo.id
              alert_number = 1
              alert_id = 100

              # create several revisions
              [
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-30")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-29")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-28")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
              ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
                create(
                  :soa_code_scanning_alert_revision,
                  repository_id:,
                  alert_number:,
                  alert_id:,
                  date: date,
                  next_revision_date_id: next_date_id,
                  alert_created_at: Time.parse("2023-11-25"),
                  alert_updated_at: date.date_value,
                  created_at: date.date_value,
                )
                next date.id
              end

              # mock turboscan reconciliation response with alert number and id set to the correct values
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_id,
                        number: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                      ),
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_id,
                        number: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: Time.parse("2023-11-28T13:00:00Z"), # latest revision, after our revision on date
                      ),
                    ]
                  )
                ))

              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

              # assert that there is still a 'latest' revision based on alert_id
              latest_revision = CodeScanningAlertRevision
                .find_by(
                  repository_id:,
                  alert_id:,
                  next_revision_date_id: Date::FUTURE_DATE_ID,
                )
              assert latest_revision
              assert_equal "2023-11-28", latest_revision&.alert_updated_at&.to_date.to_s

              # assert the post-dated revisions are purged
              revision_dates = CodeScanningAlertRevision.where(repository_id: @repo.id, alert_number: alert_number).pluck(:date_id)
              expected_dates = [20231128, 20231127, 20231126, 20231125]
              assert_same_elements expected_dates, revision_dates

              assert_dogstats_distribution(1, "security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist")
              assert_dogstats_count_value(2, "security_overview_analytics.reconciliation.revisions_purged")
            end

            context "when extraneous revisions have older alert_update_at timestamp" do
              test "it purges any extraneous revisions based on alert_id" do
                repository_id = @repo.id
                alert_number = 1
                alert_id = 100
                alert_updated_at = Time.parse("2023-11-26T08:00:00Z")

                # create several revisions
                [
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-30")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-29")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-28")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
                ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
                  create(
                    :soa_code_scanning_alert_revision,
                    repository_id:,
                    alert_number:,
                    alert_id:,
                    date: date,
                    next_revision_date_id: next_date_id,
                    alert_created_at: Time.parse("2023-11-25"),
                    alert_updated_at: date.date_value >= alert_updated_at ? alert_updated_at.to_date : date.date_value,
                    created_at: date.date_value,
                  )
                  next date.id
                end

                # mock turboscan reconciliation response where updated_at is prior to our latest revision
                ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                      alerts: [
                        ::Turboscan::Proto::InsightsAlert.new(
                          repository_id: @repo.id,
                          id: alert_id,
                          number: alert_number,
                          created_at: Time.parse("2023-11-25"),
                          updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                        ),
                        ::Turboscan::Proto::InsightsAlert.new(
                          repository_id: @repo.id,
                          id: alert_id,
                          number: alert_number,
                          created_at: Time.parse("2023-11-25"),
                          updated_at: alert_updated_at, # latest revision, after our revision on date
                        ),
                      ]
                    )
                  ))

                # run reconciliation
                CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

                # assert that there is still a 'latest' revision
                latest_revision = CodeScanningAlertRevision
                  .find_by(
                    repository_id:,
                    alert_id:,
                    next_revision_date_id: Date::FUTURE_DATE_ID,
                  )
                assert latest_revision
                assert_equal "2023-11-26", latest_revision&.alert_updated_at&.to_date.to_s

                # assert the post-dated revisions are purged
                revision_dates = CodeScanningAlertRevision.where(repository_id: @repo.id, alert_id:).pluck(:date_id)
                expected_dates = [20231126, 20231125]
                assert_same_elements expected_dates, revision_dates

                assert_dogstats_distribution(1, "security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist")
                assert_dogstats_count_value(4, "security_overview_analytics.reconciliation.revisions_purged")
              end

              test "extraneous revisions are purged even despite the broken revision chain" do
                repository_id = @repo.id
                alert_number = 1
                alert_updated_at = Time.parse("2023-11-26T08:00:00Z")

                # create several revisions
                [
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-30")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-29")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-28")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
                  create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
                ].reduce("20231131") do |next_date_id, date|
                  create(
                    :soa_code_scanning_alert_revision,
                    repository_id:,
                    alert_number:,
                    date: date,
                    next_revision_date_id: date.date_value == alert_updated_at.to_date ? Date::FUTURE_DATE_ID : next_date_id,
                    alert_created_at: Time.parse("2023-11-25"),
                    alert_updated_at: date.date_value >= alert_updated_at.to_date ? alert_updated_at.to_date : date.date_value,
                    created_at: date.date_value,
                  )
                  next date.id
                end

                # mock turboscan reconciliation response where updated_at is prior to our latest revision
                ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                      alerts: [
                        ::Turboscan::Proto::InsightsAlert.new(
                          repository_id: @repo.id,
                          id: alert_number,
                          created_at: Time.parse("2023-11-25"),
                          updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                        ),
                        ::Turboscan::Proto::InsightsAlert.new(
                          repository_id: @repo.id,
                          id: alert_number,
                          created_at: Time.parse("2023-11-25"),
                          updated_at: alert_updated_at, # latest revision, after our revision on date
                        ),
                      ]
                    )
                  ))

                # run reconciliation
                CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

                # assert that there is still a 'latest' revision
                latest_revision = CodeScanningAlertRevision
                  .find_by(
                    repository_id:,
                    alert_number:,
                    next_revision_date_id: Date::FUTURE_DATE_ID,
                  )
                assert latest_revision
                assert_equal "2023-11-26", latest_revision&.alert_updated_at&.to_date.to_s

                # assert the post-dated revisions are not purged
                revision_dates = CodeScanningAlertRevision.where(repository_id: @repo.id, alert_number: alert_number).pluck(:date_id)
                expected_dates = [20231126, 20231125]
                assert_same_elements expected_dates, revision_dates

                assert_dogstats_distribution(1, "security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist")
                assert_dogstats_count_value(4, "security_overview_analytics.reconciliation.revisions_purged")
              end
            end
          end

          context "when analytics does not have revisions dated after the logical alert" do
            test "it does not purge any extraneous revisions" do
              repository_id = @repo.id
              alert_number = 1

              # create several revisions
              [
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-30")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-29")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-28")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
              ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
                create(
                  :soa_code_scanning_alert_revision,
                  repository_id:,
                  alert_number:,
                  date: date,
                  next_revision_date_id: next_date_id,
                  alert_created_at: Time.parse("2023-11-25"),
                  alert_updated_at: date.date_value,
                  created_at: date.date_value,
                )
                next date.id
              end

              # mock turboscan reconciliation response where updated_at is prior to our latest revision
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                      ),
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: Time.parse("2023-11-30"), # latest revision
                      ),
                    ]
                  )
                ))

              # confirm starting revision count
              assert_equal 6, CodeScanningAlertRevision.where(repository_id: @repo.id, alert_number: alert_number).count

              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

              # assert that there is still a 'latest' revision
              latest_revision = CodeScanningAlertRevision
                .find_by(
                  repository_id:,
                  alert_number:,
                  next_revision_date_id: Date::FUTURE_DATE_ID,
                )
              assert latest_revision
              assert_equal "2023-11-30", latest_revision&.alert_updated_at&.to_date.to_s

              # confirm starting revision count
              assert_equal 6, CodeScanningAlertRevision.where(repository_id: @repo.id, alert_number: alert_number).count

              refute_dogstats_distribution("security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist")
              refute_dogstats_count("security_overview_analytics.reconciliation.revisions_purged")
            end
          end

          context "when reconciliation is run in dry run mode" do
            test "it doesn't purge any revisions, only logs" do
              FeatureFlagHelper.stubs(:code_scanning_reconciliation_dry_run_mode?).returns(true)

              repository_id = @repo.id
              alert_number = 1
              alert_id = 100
              alert_updated_at = Time.parse("2023-11-26T08:00:00Z")

              # create several revisions
              [
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-30")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-29")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-28")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
                create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
              ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
                create(
                  :soa_code_scanning_alert_revision,
                  repository_id:,
                  alert_number:,
                  alert_id:,
                  date: date,
                  next_revision_date_id: next_date_id,
                  alert_created_at: Time.parse("2023-11-25"),
                  alert_updated_at: date.date_value >= alert_updated_at ? alert_updated_at.to_date : date.date_value,
                  created_at: date.date_value,
                )
                next date.id
              end

              # mock turboscan reconciliation response where updated_at is prior to our latest revision
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_id,
                        number: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                      ),
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: alert_id,
                        number: alert_number,
                        created_at: Time.parse("2023-11-25"),
                        updated_at: alert_updated_at, # latest revision, after our revision on date
                      ),
                    ]
                  )
                ))

              GitHub.logger.expects(:info).with("Alert revisions would be purged",
                has_entries({
                  "gh.security_overview_analytics.alert.id": alert_id,
                  "gh.security_overview_analytics.alert.number": alert_number,
                  "gh.security_overview_analytics.revisions_purged": 4,
                })
                ).once

              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

              revision_dates = CodeScanningAlertRevision.where(repository_id: @repo.id, alert_number: alert_number).pluck(:date_id)
              expected_dates = [20231130, 20231129, 20231128, 20231127, 20231126, 20231125]
              assert_same_elements expected_dates, revision_dates

              refute_dogstats_distribution "security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist"
              refute_dogstats_count "security_overview_analytics.reconciliation.revisions_purged"
            end
          end
        end

        context "#purge_revisions_dup_after_latest" do
          test "purges dup revisions existed after latest revision" do
            date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
            date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
            date3 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-22"))
            date4 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-23"))

            # latest revision
            rev1 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date1, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value, created_at: date1.date_value)
            # redundant revisions
            rev2 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date2, next_revision_date_id: date3.id, alert_created_at: date1.date_value, created_at: date2.date_value)
            rev3 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date3, next_revision_date_id: date4.id, alert_created_at: date1.date_value, created_at: date3.date_value)

            # current alert
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date1.date_value.to_s), # initial revision, dates match
                    ),
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date4.date_value.to_s),
                    ),
                  ]
                )
              ))

            # run reconciliation
            perform_enqueued_jobs only: [CodeScanningAlertRevisionIngestionJob] do
              assert_nothing_raised do
                CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
              end
            end

            # Redundant revisions deleted
            assert_nil CodeScanningAlertRevision.find_by(id: rev2.id)
            assert_nil CodeScanningAlertRevision.find_by(id: rev3.id)

            # New alert revision upserted
            latest_revision = CodeScanningAlertRevision.find_by(repository_id: @repo.id, alert_number: rev1.alert_number, next_revision_date_id: Date::FUTURE_DATE_ID)
            assert latest_revision
            assert_equal date4.id, T.must(latest_revision).date_id

            # Previous latest revision now points at newly upserted revision
            assert_equal date4.id, rev1.reload.next_revision_date_id

            assert_dogstats_distribution(1, "security_overview_analytics.reconciliation.purge_revisions_dup_after_latest.dist")
            assert_dogstats_count_value(2, "security_overview_analytics.reconciliation.redundant_revisions_purged")
          end

          test "does not purge unexpected revisions with different state and reports them instead" do
            date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
            date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
            date3 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-22"))
            date4 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-23"))

            # latest revision
            rev1 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date1, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value, created_at: date1.date_value)
            # redundant revision
            rev2 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date2, next_revision_date_id: date3.id, alert_created_at: date1.date_value, created_at: date2.date_value)
            # unexpected revision
            rev3 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date3, next_revision_date_id: date4.id, alert_resolved: true, alert_created_at: date1.date_value, created_at: date3.date_value)

            # current alert
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date1.date_value.to_s), # initial revision, dates match
                    ),
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date4.date_value.to_s),
                    ),
                  ]
                )
              ))

            # run reconciliation
            assert_nothing_raised do
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
            end

            # Redundant revision deleted
            assert_nil CodeScanningAlertRevision.find_by(id: rev2.id)
            # Unexpected revision not deleted
            refute_nil CodeScanningAlertRevision.find_by(id: rev3.id)

            assert_dogstats_increment(1, "security_overview_analytics.reconciliation.unexpected_revision")
            assert_dogstats_distribution(1, "security_overview_analytics.reconciliation.purge_revisions_dup_after_latest.dist")
            assert_dogstats_count_value(1, "security_overview_analytics.reconciliation.redundant_revisions_purged")
          end

          test "does not purge revisions when reconciliation job in dry_run mode" do
            FeatureFlagHelper.stubs(:code_scanning_reconciliation_dry_run_mode?).returns(true)

            date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
            date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
            date3 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-22"))
            date4 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-23"))

            # latest revision
            rev1 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date1, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value, created_at: date1.date_value)
            # redundant revisions
            rev2 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date2, next_revision_date_id: date3.id, alert_created_at: date1.date_value, created_at: date2.date_value)
            rev3 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date3, next_revision_date_id: date4.id, alert_created_at: date1.date_value, created_at: date3.date_value)

            # current alert
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date1.date_value.to_s), # initial revision, dates match
                    ),
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: rev1.alert_id,
                      number: rev1.alert_number,
                      created_at: Time.parse(date1.date_value.to_s),
                      updated_at: Time.parse(date4.date_value.to_s),
                    ),
                  ]
                )
              ))

            # run reconciliation
            assert_nothing_raised do
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
            end

            # Redundant revisions not deleted
            refute_nil CodeScanningAlertRevision.find_by(id: rev2.id)
            refute_nil CodeScanningAlertRevision.find_by(id: rev3.id)

            refute_dogstats_distribution("security_overview_analytics.reconciliation.purge_revisions_dup_after_latest.dist")
            refute_dogstats_count("security_overview_analytics.reconciliation.redundant_revisions_purged")
          end
        end

        context "purging orphaned alerts" do
          context "when reconciliation is run in dry run mode" do
            test "it doesn't purge any revisions, only logs" do
              FeatureFlagHelper.stubs(:code_scanning_reconciliation_dry_run_mode?).returns(true)

              date = create(:soa_date, date_value: Time.parse("2023-12-10"))
              end_date = create(:soa_date, date_value: Time.parse("9999-12-31"))

              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 100, alert_id: 100, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 200, alert_id: 200, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 300, alert_id: 300, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 400, alert_id: 400, date:, next_revision_date: end_date)

              # mock turboscan reconciliation response where updated_at is prior to our latest revision
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: 100,
                        number: 1,
                        updated_at: Time.parse("2023-12-10"),
                        severity: :CRITICAL,
                        tool_name: "CodeQL",
                        rule_sarif_identifier: "rb/unsafe-deserialization",
                      ),
                      # NOTE: alert 2 is missing
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: 300,
                        number: 3,
                        updated_at: Time.parse("2023-12-10"),
                        severity: :CRITICAL,
                        tool_name: "CodeQL",
                        rule_sarif_identifier: "rb/unsafe-deserialization",
                      ),
                      # NOTE: alert 4 is missing
                    ]
                  )
                ))

              GitHub.logger.expects(:info).with("Orphaned alerts would be processed",
                has_entries({
                  "gh.security_overview_analytics.job.orphaned_alerts_count": 2,
                  "gh.security_overview_analytics.job.orphaned_alerts_number_and_id": [[200, 200], [400, 400]]
                })
                ).once

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).never
              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

              refute_dogstats_count "security_overview_analytics.reconciliation.deviation"
            end

            test "logs telemetry in batches if a high number of alerts are impacted" do
              FeatureFlagHelper.stubs(:code_scanning_reconciliation_dry_run_mode?).returns(true)

              date = create(:soa_date, date_value: Time.parse("2023-12-10"))
              end_date = create(:soa_date, date_value: Time.parse("9999-12-31"))

              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 100, alert_id: 100, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 200, alert_id: 200, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 300, alert_id: 300, date:, next_revision_date: end_date)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 400, alert_id: 400, date:, next_revision_date: end_date)

              # mock turboscan reconciliation response where updated_at is prior to our latest revision
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: 100,
                        number: 1,
                        updated_at: Time.parse("2023-12-10"),
                        severity: :CRITICAL,
                        tool_name: "CodeQL",
                        rule_sarif_identifier: "rb/unsafe-deserialization",
                      ),
                      # NOTE: alert 2 is missing
                      # NOTE: alert 3 is missing
                      # NOTE: alert 4 is missing
                    ]
                  )
                ))

              GitHub.logger.expects(:info).with("Orphaned alerts would be processed",
                has_entries({
                  "gh.security_overview_analytics.job.orphaned_alerts_count": 3,
                  "gh.security_overview_analytics.job.orphaned_alerts_number_and_id": [[200, 200], [300, 300]],
                })
                ).once

              GitHub.logger.expects(:info).with("Orphaned alerts would be processed",
                has_entries({
                  "gh.security_overview_analytics.job.orphaned_alerts_count": 3,
                  "gh.security_overview_analytics.job.orphaned_alerts_number_and_id": [[400, 400]],
                })
                ).once

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).never
              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.stub_const(:TELEMETRY_BATCH_SIZE, 2) do
                CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
              end

              refute_dogstats_count "security_overview_analytics.reconciliation.deviation"
            end
          end

          context "when analytics has alerts no longer present in the source" do
            test "it enqueues a job to purge the alert" do
              date = create(:soa_date, date_value: Time.parse("2023-12-11"))
              end_date = create(:soa_date, date_value: Time.parse("9999-12-31"))

              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 1, alert_id: 100, date:)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 2, alert_id: 200, date:)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, alert_id: 300, date:)
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 4, alert_id: 400, date:)

              # mock turboscan reconciliation response where updated_at is prior to our latest revision
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: 100,
                        number: 1,
                        updated_at: Time.parse("2023-12-10"),
                      ),
                      # NOTE: alert 2 is missing
                      ::Turboscan::Proto::InsightsAlert.new(
                        repository_id: @repo.id,
                        id: 300,
                        number: 3,
                        updated_at: Time.parse("2023-12-10"),
                      ),
                      # NOTE: alert 4 is missing
                    ]
                  )
                ))

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).at_least(2)
              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).with do |**kwargs|
                kwargs[:alert].id == 200 &&
                kwargs[:alert].number == 2 &&
                kwargs[:alert].repository_id == @repo.id &&
                kwargs[:deleted] == true
              end.once
              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).with do |**kwargs|
                kwargs[:alert].id == 400 &&
                kwargs[:alert].number == 4 &&
                kwargs[:alert].repository_id == @repo.id &&
                kwargs[:deleted] == true
              end.once

              # run reconciliation
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
            end
          end
        end

        context "when alert exceeds retention limit" do
          test "it ignores fake initial revision" do
            # no revisions
            CodeScanningAlertRevision.delete_all

            # mock return of an alert with its initial and the latest revision
            updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
            created_at = (updated_at - 1.day).to_time

            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [
                    ::Turboscan::Proto::InsightsAlert.new(
                      id: 1,
                      repository_id: @repo.id,
                      created_at: created_at,
                      updated_at: created_at,
                      resolution: nil,
                    ),
                    ::Turboscan::Proto::InsightsAlert.new(
                      id: 1,
                      repository_id: @repo.id,
                      created_at: created_at,
                      updated_at: updated_at,
                      resolution: nil,
                    )
                  ]
                )
              ))

            CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with do |kwargs|
                kwargs[:alert].id == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == created_at.utc
              end
              .never
            CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with do |kwargs|
                kwargs[:alert].id == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == updated_at.utc
              end
              .once
            Session.any_instance.expects(:reset!).never

            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")

            assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
            assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: ["reason:exceeds_retention_limit"]
          end
        end
      end

      context "when the organization_id is not provided" do
        test "it raises ArgumentError" do
          assert_no_enqueued_jobs(only: CodeScanningAlertsDeviationDetectionJob) do
            assert_raises_with_message(ArgumentError, "Missing repository_id.") do
              CodeScanningAlertsDeviationDetectionJob.perform_later(session_id: "foo")
            end

            refute CodeScanningAlertsDeviationDetectionJob.new.locked?
          end
        end
      end

      context "when on GHES", enterprise_only: true do
        test "it doesn't perform the job if feature not configured" do
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:get_alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningAlertsDeviationDetectionJob) do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"])
        end
      end

      context "when the organization is not in scope" do
        test "it doesn't perform the job" do
          TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:get_alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningAlertsDeviationDetectionJob) do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"])
        end
      end

      context "when the organization has not been initialized" do
        test "it doesn't perform the job" do
          Initialization.any_instance.stubs(:initialized?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:get_alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningAlertsDeviationDetectionJob) do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"])
        end
      end

      context "when session has been reset" do
        test "it doesn't peform the job" do
          Session.any_instance.stubs(:session_started_at).returns(nil)
          Session.any_instance.expects(:reset!).never

          assert_performed_jobs 1, only: CodeScanningAlertsDeviationDetectionJob do
            CodeScanningAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id)
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "resiliency" do
        test "it retries on standard conditions" do
          assert_retry_conditions(
            job: CodeScanningAlertsDeviationDetectionJob,
            args: [repository_id: @repo.id, session_id: "foo"],
            using_kwargs: true
          )
        end

        test "it retries on turboscan error" do
          ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
            .returns(Twirp::ClientResp.new(
              error: Twirp::Error.new(
                :invalid_argument,
                "repository_id is required"
              )
            ))

          assert_enqueued_with(
              job: CodeScanningAlertsDeviationDetectionJob,
              args: [repository_id: @repo.id, session_id: "foo"]) do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
          end
        end
      end

      context "batched job" do
        context "when result includes a continuation cursor" do
          test "it enqueues a continuation job" do
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [
                    ::Turboscan::Proto::InsightsAlert.new(
                      repository_id: @repo.id,
                      id: 123,
                      created_at: Time.parse("2023-11-25"),
                      updated_at: Time.parse("2023-11-25"), # initial revision, dates match
                    ),
                  ],
                  next_cursor: "but-wait-theres-more",
                )
              ))

            expected_args = ->(job_args) do
              assert_equal @repo.id, job_args.first[:repository_id]
              assert_equal [123, "but-wait-theres-more"], job_args.first[:offset_item_id]
            end
            assert_enqueued_with(job: CodeScanningAlertsDeviationDetectionJob, args: expected_args) do
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
            end
          end
        end

        context "when result does not include a continuation cursor" do
          test "it does not enqueue a continuation job" do
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts: [],
                  next_cursor: "",
                )
              ))

            assert_no_enqueued_jobs(only: CodeScanningAlertsDeviationDetectionJob) do
              CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo")
            end
          end
        end

        test "it handles offset_item_id as an Integer" do
          assert_nothing_raised do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo", offset_item_id: 123)
          end
        end

        test "it handles offset_item_id as a Tuple" do
          assert_nothing_raised do
            CodeScanningAlertsDeviationDetectionJob.perform_now(repository_id: @repo.id, session_id: "foo", offset_item_id: [123, "some_cursor"])
          end
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same organization" do
          assert_enqueued_jobs 1, only: CodeScanningAlertsDeviationDetectionJob do
            CodeScanningAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: "foo")
            CodeScanningAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: "bar")
          end
        end
      end
    end
  end
end
