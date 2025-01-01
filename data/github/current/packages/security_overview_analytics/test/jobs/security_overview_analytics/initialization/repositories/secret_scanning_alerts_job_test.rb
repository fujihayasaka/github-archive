# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class SecretScanningAlertsJobTest < GitHub::TestCase
        include DogstatsTestHelpers
        include JobTestHelper

        SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
        SecretScanningBackfillResponse = ::GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequestResponse

        fixtures do
          @biz = create(:business)
          @org = create(:organization, business: @biz)
          @repo = create(:repository, owner: @org, name: "foo")
          @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
          @user = create(:user)
          @user_repo = create(:repository, owner: @user, force_user_owned: true)
        end

        setup do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

          if GitHub.enterprise?
            SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
          end
        end

        context "#perform" do
          test "queues alert ingestion job for org" do
            now = Time.now
            yesterday = 1.day.ago.to_time

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: yesterday,
                      updated_at: yesterday
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: yesterday,
                      updated_at: now
                    })
                  ]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == yesterday.utc }
              .once
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc }
              .once

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            refute_dogstats_increment "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped"
          end

          test "queues alert ingestion job for user" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

            now = Time.now
            yesterday = 1.day.ago.to_time

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: yesterday,
                      updated_at: yesterday
                    }),
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: yesterday,
                      updated_at: now
                    })
                  ]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == yesterday.utc }
              .once
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc }
              .once

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @user_repo.id)
              end
            end

            refute_dogstats_increment "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped"
          end

          test "skips initial alert revision if it has later revision exceeds retention limit" do
            updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
            created_at = (updated_at - 1.day).to_time

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: created_at
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: updated_at
                    })
                  ]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == created_at.utc }
              .never
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == updated_at.utc }
              .once

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:exceeds_retention_limit"]
          end

          test "skips the initial revision if any revision already exists" do
            existing_revision = create(
              :soa_secret_scanning_alert_revision,
              repository_id: @repo.id,
              alert_number: 1,
              date_id: 20231001,
              alert_created_at: Time.parse("2023-10-01T01:02:03Z"),
              alert_updated_at: Time.parse("2023-10-01T01:02:03Z")
            )

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 1,
                    created_at: Time.parse("2023-10-01T01:02:03Z"),
                    updated_at: Time.parse("2023-10-01T01:02:03Z")
                  })]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:revision_already_exists"]
          end

          test "skips the revision if a non-initial revision already exists" do
            existing_revision = create(
              :soa_secret_scanning_alert_revision,
              repository_id: @repo.id,
              alert_number: 1,
              date_id: 20231001,
              alert_created_at: Time.parse("2023-09-30T01:02:03Z"),
              alert_updated_at: Time.parse("2023-10-01T01:02:03Z")
            )

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 1,
                    created_at: Time.parse("2023-09-30T01:02:03Z"),
                    updated_at: Time.parse("2023-10-01T01:02:03Z")
                  })]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:revision_already_exists"]
          end

          test "does not skip a non-initial revision if an initial revision exists" do
            now = Time.now
            two_min_ago = 2.minutes.ago.to_time
            date_two_min_ago = create(:security_overview_analytics_date, date_value: two_min_ago.utc)
            existing_revision = create(
              :soa_secret_scanning_alert_revision,
              repository_id: @repo.id,
              alert_number: 1,
              date: date_two_min_ago,
              alert_created_at: Time.parse("2023-10-01T01:02:03Z"),
              alert_updated_at: Time.parse("2023-10-01T01:02:03Z")
            )

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 1,
                    created_at: Time.parse("2023-10-01T01:02:03Z"),
                    updated_at: Time.parse("2023-10-01T01:05:03Z")
                  })]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).once

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            refute_dogstats_increment "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped"
          end

          test "skips revisions from low confidence alerts" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 1,
                    created_at: Time.parse("2023-10-01T01:02:03Z"),
                    updated_at: Time.parse("2023-10-01T01:02:03Z"),
                    low_confidence: true
                  })]
                })
              ))
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            perform_enqueued_jobs only: SecretScanningAlertsJob do
              assert_nothing_raised do
                SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:low_confidence_alert"]
          end
        end

        context "#around_enqueue" do
          test "raises ArgumentError if missing repository_id" do
            assert_enqueued_jobs 0, only: SecretScanningAlertsJob do
              assert_raises ArgumentError do
                SecretScanningAlertsJob.perform_later
              end
            end
          end
        end

        context "#around_perform" do
          test "skips the perform by subsequent batch if repo is soft-deleted" do
            repo = create(:deleted_repository, owner: @org)

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill).never
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            assert_performed_jobs 1, only: SecretScanningAlertsJob do
              SecretScanningAlertsJob.perform_later(repository_id: repo.id, offset_item_id: "next_cursor")
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:repository_deleted"]
          end

          test "skips the perform by subsequent batch if tenant out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill).never
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            assert_performed_jobs 1, only: SecretScanningAlertsJob do
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: "next_cursor")
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:tenant_not_in_scope"]
          end

          test "skips the perform by subsequent batch if feature is not available on GHES", enterprise_only: true do
            SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).never
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

            assert_performed_jobs 1, only: SecretScanningAlertsJob do
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: "next_cursor")
            end

            assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped", tags: ["reason:feature_unavailable"]
          end
        end

        context "batched job" do
          test "queues subsequent jobs" do
            now = Time.now
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  next_cursor: nil
                }).to_h
              )
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  next_cursor: "theres_more",
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 1,
                    created_at: now,
                    updated_at: now
                  })]
                })
              ))
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  next_cursor: "theres_more"
                }).to_h
              )
              .returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [SecretScanningAlert.new({
                    repository_id: @repo.id,
                    number: 2,
                    created_at: now,
                    updated_at: now
                  })]
                })
              ))

            assert_enqueued_jobs 2, only: SecretScanningAlertRevisionIngestionJob do
              assert_performed_jobs 2, only: SecretScanningAlertsJob do
                perform_enqueued_jobs only: SecretScanningAlertsJob do
                  assert_nothing_raised do
                    SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
                  end
                end
              end
            end

            assert_dogstats_distribution 1, "batched_job.total_time.dist"
          end
        end

        context "resiliency" do
          test "retries on standard conditions" do
            assert_retry_conditions(
              job: SecretScanningAlertsJob,
              args: [{ repository_id: @repo.id }],
              using_kwargs: true
            )
          end

          test "retries on token scanning API error" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_alerts_for_insights_backfill)
              .returns(Twirp::ClientResp.new(
                error: Twirp::Error.new(
                  :invalid_argument,
                  "something is wrong"
                ),
                data: nil
              ))
            assert_enqueued_with(job: SecretScanningAlertsJob, args: [{ repository_id: @repo.id }]) do
              SecretScanningAlertsJob.perform_now(repository_id: @repo.id)
            end
            assert_dogstats_increment 1,
              "security_overview_analytics.initialization.repository_secret_scanning_alerts.error",
              tags: ["reason:#{SecretScanningAlertsJob::TokenScanningServiceMetricsApiError.name&.underscore}}"]
          end

          test "does not allow concurrent jobs for the same repository" do
            assert_enqueued_jobs 1, only: SecretScanningAlertsJob do
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
            end
          end
        end

        context "hash lock" do
          test "allows one job per repo to be enqueued" do
            other_repo = create(:repository, owner: @org, name: "bar")
            assert_enqueued_jobs 2, only: SecretScanningAlertsJob do
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              SecretScanningAlertsJob.perform_later(repository_id: @repo.id)
              SecretScanningAlertsJob.perform_later(repository_id: other_repo.id)
            end
          end
        end
      end
    end
  end
end
