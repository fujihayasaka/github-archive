# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class CodeScanningAlertsJobTest < GitHub::TestCase
        include DogstatsTestHelpers
        include JobTestHelper

        fixtures do
          @biz = create(:business)
          @org = create(:organization, business: @biz)
          @repo = create(:repository, owner: @org, name: "foo")
          @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
        end

        setup do
          if GitHub.enterprise?
            SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
          end
        end

        test "it enqueues ingestion job for each alert in response" do
          alerts = 5.times.map do |i|
            ::Turboscan::Proto::InsightsAlert.new(
              id: (i + 1),
              repository_id: @repo.id,
              created_at: Time.now.utc,
              closed_at: nil,
              updated_at: Time.now.utc,
              closed: false,
              resolution: :NO_RESOLUTION,
              rule_name: "Cross-Site Scripting",
              rule_sarif_identifier: "rb/xss",
              tool_name: "CodeQL",
              severity: :HIGH,
              present_on_default_ref: true,
            )
          end
          ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                alerts:
              )
            ))

          assert_enqueued_jobs(alerts.length, only: CodeScanningAlertRevisionIngestionJob) do
            Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
          end
        end

        test "skips initial alert revision if it has later revision exceeds retention limit" do
          updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
          date_id_updated_at = Date.id_from_time(updated_at)
          created_at = (updated_at - 1.day).to_time
          date_id_created_at = Date.id_from_time(created_at)

          ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                alerts: [
                  ::Turboscan::Proto::InsightsAlert.new(
                    id: 1,
                    repository_id: @repo.id,
                    created_at: created_at,
                    closed_at: nil,
                    updated_at: created_at,
                    closed: false,
                    resolution: :NO_RESOLUTION,
                    rule_name: "Cross-Site Scripting",
                    rule_sarif_identifier: "rb/xss",
                    tool_name: "CodeQL",
                    severity: :HIGH,
                    present_on_default_ref: true,
                  ),
                  ::Turboscan::Proto::InsightsAlert.new(
                    id: 1,
                    repository_id: @repo.id,
                    created_at: created_at,
                    closed_at: nil,
                    updated_at: updated_at,
                    closed: false,
                    resolution: :NO_RESOLUTION,
                    rule_name: "Cross-Site Scripting",
                    rule_sarif_identifier: "rb/xss",
                    tool_name: "CodeQL",
                    severity: :HIGH,
                    present_on_default_ref: true,
                  )
                ]
              )
            ))
          CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].id == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:date_id] == date_id_created_at }
            .never
          CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].id == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:date_id] == date_id_updated_at }
            .once

          Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)

          assert_dogstats_increment 1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["cause:exceeds_retention_limit"]
        end

        context "query by alert_number or alert_id" do
          test "queries existing revisions by alert_id AND alert_id = alert_number and skips the initial revision iff read_alert_id flag is on and read_alert_number is off" do
            FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(true)
            FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(false)
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, alert_id: 101, date_id: 20231002)
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_id: 1, alert_number: 1, date_id: 20231002)

            alerts = 5.times.map do |i|
              ::Turboscan::Proto::InsightsAlert.new(
                id: (i + 1),
                number: (i + 1),
                repository_id: @repo.id,
                created_at: Time.parse("2023-10-02T01:02:03Z"),
                closed_at: nil,
                updated_at: Time.parse("2023-10-02T01:02:03Z"),
                closed: false,
                resolution: :NO_RESOLUTION,
                rule_name: "Cross-Site Scripting",
                rule_sarif_identifier: "rb/xss",
                tool_name: "CodeQL",
                severity: :HIGH,
                present_on_default_ref: true,
              )
            end
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts:
                )
              ))

            CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].id != 1 }
            .times(alerts.length - 1)

            Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
          end

          test "queries existing revisions by alert_number and skips the initial revision iff read_alert_number flag is on and read_alert_id is off" do
            FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(true)
            FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(false)
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, alert_id: 101, date_id: 20231002)
            create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_id: 1, alert_number: 101, date_id: 20231002)

            alerts = 5.times.map do |i|
              ::Turboscan::Proto::InsightsAlert.new(
                id: (i + 1),
                number: (5 - i),
                repository_id: @repo.id,
                created_at: Time.parse("2023-10-02T01:02:03Z"),
                closed_at: nil,
                updated_at: Time.parse("2023-10-02T01:02:03Z"),
                closed: false,
                resolution: :NO_RESOLUTION,
                rule_name: "Cross-Site Scripting",
                rule_sarif_identifier: "rb/xss",
                tool_name: "CodeQL",
                severity: :HIGH,
                present_on_default_ref: true,
              )
            end
            ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                  alerts:
                )
              ))

            CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].number != 3 }
            .times(alerts.length - 1)

            Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
          end
        end

        context "when the repository_id is not provided" do
          test "it raises ArgumentError" do
            assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob) do
              assert_raises_with_message(ArgumentError, "Missing repository_id.") do
                Repositories::CodeScanningAlertsJob.perform_later
              end
            end
          end
        end

        context "when the repository is soft-deleted" do
          test "it doesn't perform the first job" do
            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            repo = create(:deleted_repository, owner: @org)
            assert_no_performed_jobs(only: Repositories::CodeScanningAlertsJob) do
              # perform_now to skip enqueueing; simulate already-enqueued job before condition shipped
              Repositories::CodeScanningAlertsJob.perform_now(repository_id: repo.id)
            end
          end

          test "it doesn't perform subsequent jobs" do
            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            repo = create(:deleted_repository, owner: @org)
            assert_performed_jobs(1, only: Repositories::CodeScanningAlertsJob) do
              Repositories::CodeScanningAlertsJob.perform_later(repository_id: repo.id, offset_item_id: "foo")
            end
          end
        end

        context "when the repository is not org-owned" do
          test "it doesn't perform the first job" do
            repo = create(:repository)

            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            assert_no_performed_jobs(only: Repositories::CodeScanningAlertsJob) do
              # perform_now to skip enqueueing; simulate already-enqueued job before condition shipped
              Repositories::CodeScanningAlertsJob.perform_now(repository_id: repo.id)
            end

            assert_dogstats_increment(1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["reason:not_org_owned_repo"])
          end

          test "it doesn't perform subsequent jobs" do
            repo = create(:repository)

            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            assert_performed_jobs(1, only: Repositories::CodeScanningAlertsJob) do
              Repositories::CodeScanningAlertsJob.perform_later(repository_id: repo.id, offset_item_id: "foo")
            end

            assert_dogstats_increment(1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["reason:not_org_owned_repo"])
          end
        end

        context "when the repository owner is not in scope" do
          test "it doesn't perform the first job" do
            TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)

            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            assert_no_performed_jobs(only: Repositories::CodeScanningAlertsJob) do
              # perform_now to skip enqueueing; simulate already-enqueued job before condition shipped
              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end

            assert_dogstats_increment(1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["reason:tenant_not_in_scope"])
          end

          test "it doesn't perform subsequent jobs" do
            TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)

            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            assert_performed_jobs(1, only: Repositories::CodeScanningAlertsJob) do
              Repositories::CodeScanningAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: "foo")
            end

            assert_dogstats_increment(1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["reason:tenant_not_in_scope"])
          end
        end

        context "when a revision already exists for an alert" do
          context "on the same date" do
            test "it should skip the initial revision and continue" do
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, date_id: 20231002)
              alerts = 5.times.map do |i|
                ::Turboscan::Proto::InsightsAlert.new(
                  id: (i + 1),
                  repository_id: @repo.id,
                  created_at: Time.parse("2023-10-02T01:02:03Z"),
                  closed_at: nil,
                  updated_at: Time.parse("2023-10-02T01:02:03Z"),
                  closed: false,
                  resolution: :NO_RESOLUTION,
                  rule_name: "Cross-Site Scripting",
                  rule_sarif_identifier: "rb/xss",
                  tool_name: "CodeQL",
                  severity: :HIGH,
                  present_on_default_ref: true,
                )
              end
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts:
                  )
                ))

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].id != 3 }
                .times(alerts.length - 1)

              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end

            test "it should not skip the non-initial revision if existing initial revision found" do
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, date_id: 20231002)
              alerts = 5.times.map do |i|
                ::Turboscan::Proto::InsightsAlert.new(
                  id: (i + 1),
                  repository_id: @repo.id,
                  created_at: Time.parse("2023-10-01T01:02:03Z"),
                  closed_at: nil,
                  updated_at: Time.parse("2023-10-02T01:02:03Z"),
                  closed: false,
                  resolution: :NO_RESOLUTION,
                  rule_name: "Cross-Site Scripting",
                  rule_sarif_identifier: "rb/xss",
                  tool_name: "CodeQL",
                  severity: :HIGH,
                  present_on_default_ref: true,
                )
              end
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts:
                  )
                ))

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
                .times(alerts.length)

              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end

            test "it should skip the revision if existing non-initial revision found" do
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 3, date_id: 20231002,
                alert_created_at: Time.parse("2023-10-01T01:02:03Z"),
                alert_updated_at: Time.parse("2023-10-02T01:02:03Z")
              )
              alerts = 5.times.map do |i|
                ::Turboscan::Proto::InsightsAlert.new(
                  id: (i + 1),
                  repository_id: @repo.id,
                  created_at: Time.parse("2023-10-01T01:02:03Z"),
                  closed_at: nil,
                  updated_at: Time.parse("2023-10-02T01:02:03Z"),
                  closed: false,
                  resolution: :NO_RESOLUTION,
                  rule_name: "Cross-Site Scripting",
                  rule_sarif_identifier: "rb/xss",
                  tool_name: "CodeQL",
                  severity: :HIGH,
                  present_on_default_ref: true,
                )
              end
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts:
                  )
                ))

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].id != 3 }
                .times(alerts.length - 1)

              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end
          end

          context "on a different date" do
            test "it should enqueue the ingestion job" do
              create(:soa_code_scanning_alert_revision, repository_id: @repo.id, alert_number: 1, date_id: 20231004)

              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [
                      ::Turboscan::Proto::InsightsAlert.new(
                        id: 1,
                        repository_id: @repo.id,
                        created_at: Time.parse("2023-10-01T01:02:03Z"),
                        closed_at: nil,
                        updated_at: Time.parse("2023-10-02T01:02:03Z"),
                        closed: false,
                        resolution: :NO_RESOLUTION,
                        rule_name: "Cross-Site Scripting",
                        rule_sarif_identifier: "rb/xss",
                        tool_name: "CodeQL",
                        severity: :HIGH,
                        present_on_default_ref: true,
                      )
                    ]
                  )
                ))

              CodeScanningAlertRevisionIngestionJob.expects(:perform_later).once

              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end
          end
        end

        context "when on GHES", enterprise_only: true do
          test "it doesn't perform the job if feature is not available" do
            SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)
            ::GitHub::Turboscan::Insights.expects(:get_alerts_for_insights_backfill).never

            assert_no_performed_jobs(only: Repositories::CodeScanningAlertsJob) do
              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end

            assert_dogstats_increment(1, "security_overview_analytics.initialization.code_scanning_alerts.skipped", tags: ["reason:feature_unavailable"])
          end
        end

        context "resiliency" do
          test "it retries on standard conditions" do
            assert_retry_conditions(
              job: Repositories::CodeScanningAlertsJob,
              args: [repository_id: @repo.id],
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
                job: Repositories::CodeScanningAlertsJob,
                args: [repository_id: @repo.id]) do
              Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
            end
          end

          test "does not allow concurrent jobs for the same repository" do
            assert_enqueued_jobs 1, only: CodeScanningAlertsJob do
              CodeScanningAlertsJob.perform_later(repository_id: @repo.id)
              CodeScanningAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: "foo")
            end
          end
        end

        context "batching" do
          context "when result includes a continuation cursor" do
            test "it enqueues a continuation job" do
              ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill)
                .returns(Twirp::ClientResp.new(
                  data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(
                    alerts: [],
                    next_cursor: "foo",
                  )
                ))

              expected_args = ->(job_args) do
                assert_equal @repo.id, job_args.first[:repository_id]
                assert_equal "foo", job_args.first[:offset_item_id]
              end
              assert_enqueued_with(job: Repositories::CodeScanningAlertsJob, args: expected_args) do
                Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
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

              assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob) do
                Repositories::CodeScanningAlertsJob.perform_now(repository_id: @repo.id)
              end
            end
          end
        end
      end
    end
  end
end
