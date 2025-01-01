# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../test_helpers/alert_trends_test_helpers"

module SecurityOverviewAnalytics
  module Backfill
    class AlertReopenedAtFanoutJobTest < GitHub::TestCase
      include JobTestHelper
      include ::SecurityOverviewAnalytics::Test::TestHelpers::AlertTrendsTestHelpers

      fixtures do
        create_fixtures

        @repo_2 = create(:private_repository, owner: @org).tap do |repo|
          create(:soa_repository, repository: repo)
        end
        create(
          :soa_code_scanning_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_2
        )
        create(
          :soa_secret_scanning_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_2
        )
        create(
          :soa_dependabot_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_2
        )

        @org_2 = create(:organization, business: @biz, admin: @org_admin)
        @repo_3 = create(:private_repository, owner: @org_2).tap do |repo|
          create(:soa_repository, repository: repo)
        end
        create(
          :soa_code_scanning_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_3
        )
        create(
          :soa_secret_scanning_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_3
        )
        create(
          :soa_dependabot_alert_revision,
          alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
          date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
          repository: @repo_3
        )
      end

      setup do
        enable_feature_flag(:security_center_backfill_alert_reopened_at)
      end

      context 'when feature flag "security_center_backfill_alert_reopened_at" is disabled' do
        test "it does not perform the job" do
          disable_feature_flag(:security_center_backfill_alert_reopened_at)

          perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
            AlertReopenedAtFanoutJob.perform_later
          end

          assert_no_enqueued_jobs(only: AlertReopenedAtJob)
        end
      end

      context "when features argument is specified" do
        test "it enqueues an AlertReopenedAtJob for each repository associated with the specified feature" do
          num_repos_cs = CodeScanningAlertRevision
            .select(:repository_id)
            .distinct
            .size
          num_repos_dbot = DependabotAlertRevision
            .select(:repository_id)
            .distinct
            .size
          num_repos_ss = SecretScanningAlertRevision
            .select(:repository_id)
            .distinct
            .size

          assert_equal(3, num_repos_cs)
          assert_equal(3, num_repos_dbot)
          assert_equal(3, num_repos_ss)

          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "code_scanning")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "dependabot")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "secret_scanning")).never

          perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
            AlertReopenedAtFanoutJob.perform_later(features: %w[code_scanning dependabot])
          end
        end
      end

      context "when features argument is not specified" do
        test "it enqueues an AlertReopenedAtJob for each repository associated with all features" do
          num_repos_cs = CodeScanningAlertRevision
            .select(:repository_id)
            .distinct
            .size
          num_repos_dbot = DependabotAlertRevision
            .select(:repository_id)
            .distinct
            .size
          num_repos_ss = SecretScanningAlertRevision
            .select(:repository_id)
            .distinct
            .size

          assert_equal(3, num_repos_cs)
          assert_equal(3, num_repos_dbot)
          assert_equal(3, num_repos_ss)

          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "code_scanning")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "dependabot")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "secret_scanning")).at_least(3)

          perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
            AlertReopenedAtFanoutJob.perform_later
          end
        end
      end

      context "when `owner_id`s are provided" do
        test "it enqueues an AlertReopenedAtJob for each repository in the organizations" do
          owner_ids = [@org.id]
          num_repos_cs = CodeScanningAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": owner_ids)
            .size
          num_repos_dbot = DependabotAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": owner_ids)
            .size
          num_repos_ss = SecretScanningAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": owner_ids)
            .size

          assert_equal(2, num_repos_cs)
          assert_equal(2, num_repos_dbot)
          assert_equal(2, num_repos_ss)

          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "code_scanning")).twice
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "dependabot")).twice
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "secret_scanning")).twice

          perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
            AlertReopenedAtFanoutJob.perform_later(owner_ids: owner_ids)
          end
        end
      end

      context "when `excluded_organization_id`s are provided" do
        test "it does not enqueue AlertReopenedAtJobs for the repositories in those organizations" do
          excluded_owner_ids = [@org.id]
          num_repos_cs = CodeScanningAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where.not("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": excluded_owner_ids)
            .size
          num_repos_dbot = DependabotAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where.not("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": excluded_owner_ids)
            .size
          num_repos_ss = SecretScanningAlertRevision
            .select(:repository_id)
            .distinct
            .joins(:repository_metadata)
            .where.not("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": excluded_owner_ids)
            .size

          assert_equal(1, num_repos_cs)
          assert_equal(1, num_repos_dbot)
          assert_equal(1, num_repos_ss)

          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "code_scanning")).once
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "dependabot")).once
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "secret_scanning")).once

          perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
            AlertReopenedAtFanoutJob.perform_later(excluded_owner_ids: excluded_owner_ids)
          end
        end
      end


      context "batching jobs" do
        test "queues a second job" do
          create(:private_repository, owner: @org).tap do |repo|
            create(:soa_repository, repository: repo)
          end
          create(:private_repository, owner: @org).tap do |repo|
            create(:soa_repository, repository: repo)
          end
          repo_5 = create(:private_repository, owner: @org).tap do |repo|
            create(:soa_repository, repository: repo)
          end
          create(:private_repository, owner: @org).tap do |repo|
            create(:soa_repository, repository: repo)
          end

          FanoutBaseJob.stub_const(:BATCH_SIZE, 5) do
            # validate that we queue a second job
            AlertReopenedAtFanoutJob.expects(:perform_later)
            .with { |kwargs| kwargs[:offset_item_id].first == @org.id && kwargs[:offset_item_id].second == repo_5.id }
            .once

            AlertReopenedAtFanoutJob.perform_now(owner_ids: [@org.id, @org_2.id])
          end
        end

        test "queues AlertReopenedAtJobs" do
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "code_scanning")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "dependabot")).at_least(3)
          AlertReopenedAtJob.expects(:perform_later).with(has_entries(feature: "secret_scanning")).at_least(3)

          FanoutBaseJob.stub_const(:BATCH_SIZE, 2) do
            perform_enqueued_jobs(only: AlertReopenedAtFanoutJob) do
              AlertReopenedAtFanoutJob.perform_later(owner_ids: [@org.id, @org_2.id])
            end
          end
        end
      end
    end
  end
end
