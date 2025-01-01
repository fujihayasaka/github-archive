# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class DependabotAlertsJobTest < GitHub::TestCase
        include JobTestHelper
        include DogstatsTestHelpers

        fixtures do
          @biz = create(:business)
          @org = create(:organization, business: @biz)
          @repo = create(:repository, owner: @org, name: "foo")
          @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
        end

        setup do
          if GitHub.enterprise?
            SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
          end
        end

        context "#perform" do
          context "when alerts haven't been updated since they were initially created" do
            test "it queues one alert revision job for every alert" do
              Timecop.freeze do
                alerts = 5.times.map do |i|
                  create(:repository_vulnerability_alert,
                    vulnerable_manifest_path: "package.json",
                    affects: "fake_#{i}}",
                    repository: @repo,
                    created_at: Time.now.utc,
                    updated_at: Time.now.utc
                  )
                end
              end

              assert_enqueued_jobs(5, only: DependabotAlertRevisionIngestionJob) do
                perform_enqueued_jobs(only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id)
                end
              end
            end
          end

          context "when alerts got updated after they were initially created" do
            test "it queues two alert revision jobs for every alert" do
              Timecop.freeze do
                alerts = 5.times.map do |i|
                  create(:repository_vulnerability_alert,
                    vulnerable_manifest_path: "package.json",
                    affects: "fake_#{i}}",
                    repository: @repo,
                    created_at: Time.now.utc - 1.day,
                    updated_at: Time.now.utc
                  )
                end
              end

              assert_enqueued_jobs(10, only: DependabotAlertRevisionIngestionJob) do
                perform_enqueued_jobs(only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id)
                end
              end
            end

            test "it queues the latest revision only if it was updated before retention limit" do
              Timecop.freeze do
                create(:repository_vulnerability_alert,
                  vulnerable_manifest_path: "package.json",
                  affects: "fake_alert",
                  repository: @repo,
                  created_at: Date::RETENTION_DURATION.ago - 1.week,
                  updated_at: Date::RETENTION_DURATION.ago - 1.day
                )
              end

              assert_enqueued_jobs(1, only: DependabotAlertRevisionIngestionJob) do
                perform_enqueued_jobs(only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id)
                end
              end
            end
          end
        end

        context "#around_enqueue" do
          test "raises ArgumentError if missing repository_id" do
            assert_enqueued_jobs 0, only: DependabotAlertsJob do
              assert_raises ArgumentError do
                DependabotAlertsJob.perform_later
              end
            end
          end
        end

        context "#around_perform" do
          context "when the repository is soft-deleted" do
            test "skips performing subsequent batch" do
              repo = create(:deleted_repository, owner: @org)
              assert_enqueued_jobs(0, only: DependabotAlertRevisionIngestionJob) do
                assert_performed_jobs(1, only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: repo.id, offset_item_id: 4)
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_dependabot_alerts.skipped", tags: ["reason:repository_deleted"]
            end
          end

          context "when owner is not an org" do
            test "skips performing subsequent batch" do
              user = create(:user)
              user_repo = create(:repository, owner: user, name: "foo")

              assert_enqueued_jobs(0, only: DependabotAlertRevisionIngestionJob) do
                assert_performed_jobs(1, only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: user_repo.id, offset_item_id: 4)
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_dependabot_alerts.skipped", tags: ["reason:not_org_owned_repo"]
            end
          end

          context "when org is not in scope" do
            test "skips performing initial batch" do
              TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

              assert_enqueued_jobs(0, only: DependabotAlertRevisionIngestionJob) do
                assert_performed_jobs(1, only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: 4)
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_dependabot_alerts.skipped", tags: ["reason:tenant_not_in_scope"]
            end
          end

          context "when on GHES", enterprise_only: true do
            test "skips performing subsequent batch if feature is not available" do
              SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(false)

              assert_enqueued_jobs(0, only: DependabotAlertRevisionIngestionJob) do
                assert_performed_jobs(1, only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id, offset_item_id: 4)
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.initialization.repository_dependabot_alerts.skipped", tags: ["reason:feature_unavailable"]
            end
          end
        end

        context "resiliency" do
          test "it retries on standard conditions" do
            assert_retry_conditions(
              job: Repositories::DependabotAlertsJob,
              args: [repository_id: @repo.id],
              using_kwargs: true
            )
          end
        end

        context "batch job" do
          test "queues subsequent jobs for batching" do
            Timecop.freeze do
              alerts = 5.times.map do |i|
                create(:repository_vulnerability_alert,
                  vulnerable_manifest_path: "package.json",
                  affects: "fake_#{i}}",
                  repository: @repo,
                  created_at: Time.now.utc,
                  updated_at: Time.now.utc
                )
              end
            end

            DependabotAlertsJob.stub_const(:BATCH_SIZE, 3) do
              assert_performed_jobs 2, only: DependabotAlertsJob do
                perform_enqueued_jobs(only: DependabotAlertsJob) do
                  DependabotAlertsJob.perform_later(repository_id: @repo.id)
                end
              end
            end
          end
        end

        context "hash lock" do
          test "allows one job per repo to be enqueued" do
            other_repo = create(:repository, owner: @org, name: "bar")
            assert_enqueued_jobs 2, only: DependabotAlertsJob do
              DependabotAlertsJob.perform_later(repository_id: @repo.id)
              DependabotAlertsJob.perform_later(repository_id: @repo.id)
              DependabotAlertsJob.perform_later(repository_id: other_repo.id)
            end
          end
        end
      end
    end
  end
end
