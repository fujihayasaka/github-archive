# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../test_helpers/alert_trends_test_helpers"

module SecurityOverviewAnalytics
  class Backfill::CodeScanningAlertNumberFanoutJobTest < GitHub::TestCase
    include JobTestHelper
    include ::SecurityOverviewAnalytics::Test::TestHelpers::AlertTrendsTestHelpers

    fixtures do
      create_fixtures

      @repo_2 = create(:private_repository, owner: @org).tap do |repo|
        create(:soa_repository, repository: repo)
      end
      create(
        :soa_code_scanning_alert_revision,
        alert_id: CodeScanningAlertRevision.maximum(:alert_id) + 1,
        alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
        date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
        repository: @repo_2
      )

      @org_2 = create(:organization, business: @biz, admin: @org_admin)
      repo_3 = create(:private_repository, owner: @org_2).tap do |repo|
        create(:soa_repository, repository: repo)
      end
      create(
        :soa_code_scanning_alert_revision,
        alert_id: CodeScanningAlertRevision.maximum(:alert_id) + 1,
        alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 1,
        date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
        repository: repo_3
      )
      create(
        :soa_code_scanning_alert_revision,
        alert_id: CodeScanningAlertRevision.maximum(:alert_id) + 2,
        alert_number: CodeScanningAlertRevision.maximum(:alert_id) + 2,
        date_id: ::SecurityOverviewAnalytics::Date.id_from_date(::Date.current),
        repository: repo_3
      )

      # check that we don't queue jobs for repos w/o a code scanning alert
      repo_4 = create(:private_repository, owner: @org_2).tap do |repo|
        create(:soa_repository, repository: repo)
      end
    end

    setup do
      GitHub.flipper[:security_center_backfill_code_scanning_alert_number].enable
    end

    context 'when feature flag "security_center_backfill_code_scanning_alert_number" is disabled' do
      test "it does not perform the job" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number].disable

        perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
          Backfill::CodeScanningAlertNumberFanoutJob.perform_later
        end

        assert_no_enqueued_jobs(only: Backfill::CodeScanningAlertNumberJob)
      end
    end

    context "when `organization_id`s are provided" do
      test "it enqueues a job for each repository in the organizations" do
        org_ids = [@org.id]

        perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
          Backfill::CodeScanningAlertNumberFanoutJob.perform_later(organization_ids: org_ids)
        end

        num_repos = CodeScanningAlertRevision
          .select(:repository_id)
          .distinct
          .joins(:repository_metadata)
          .where("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": org_ids)
          .size

        assert_equal(2, num_repos)
        assert_enqueued_jobs(num_repos, only: Backfill::CodeScanningAlertNumberJob)
      end
    end

    context "when `excluded_organization_id`s are provided" do
      test "it does not enqueue jobs for the repositories in those organizations" do
        excluded_org_ids = [@org.id]

        perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
          Backfill::CodeScanningAlertNumberFanoutJob.perform_later(excluded_organization_ids: excluded_org_ids)
        end

        num_repos = CodeScanningAlertRevision
          .select(:repository_id)
          .distinct
          .joins(:repository_metadata)
          .where.not("#{SecurityOverviewAnalytics::Repository.table_name}.organization_id": excluded_org_ids)
          .size

        assert_equal(1, num_repos)
        assert_enqueued_jobs(num_repos, only: Backfill::CodeScanningAlertNumberJob)
      end
    end

    context "when `backfill_mode` is provided" do
      test "it enqueues a job for each repository with the same `backfill_mode`` input" do
        Backfill::CodeScanningAlertNumberJob.expects(:perform_later).with do |kwargs|
          kwargs[:backfill_mode] == :replay
        end.times(3)

        perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
          Backfill::CodeScanningAlertNumberFanoutJob.perform_later(backfill_mode: :replay)
        end
      end
    end

    test "it enqueues a job for each repository associated with a code scanning alert" do
      perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
        Backfill::CodeScanningAlertNumberFanoutJob.perform_later
      end

      num_repos = CodeScanningAlertRevision.select(:repository_id).distinct.size

      assert_equal(3, num_repos)
      assert_enqueued_jobs(num_repos, only: Backfill::CodeScanningAlertNumberJob)
    end

    context "batching jobs" do
      test "queues a second job" do
        repo_3 = create(:private_repository, owner: @org).tap do |repo|
          create(:soa_repository, repository: repo)
        end
        repo_4 = create(:private_repository, owner: @org).tap do |repo|
          create(:soa_repository, repository: repo)
        end
        repo_5 = create(:private_repository, owner: @org).tap do |repo|
          create(:soa_repository, repository: repo)
        end
        repo_6 = create(:private_repository, owner: @org).tap do |repo|
          create(:soa_repository, repository: repo)
        end

        Backfill::CodeScanningAlertNumberFanoutJob.stub_const(:BATCH_SIZE, 5) do
          # validate that we queue a second job
          Backfill::CodeScanningAlertNumberFanoutJob.expects(:perform_later)
            .with { |kwargs| kwargs[:offset_item_id].first == @org.id && kwargs[:offset_item_id].second == repo_5.id }
            .once

          Backfill::CodeScanningAlertNumberFanoutJob.perform_now(organization_ids: [@org.id, @org_2.id])
        end
      end

      test "queues CodeScanningAlertNumberJobs" do
        Backfill::CodeScanningAlertNumberFanoutJob.stub_const(:BATCH_SIZE, 2) do
          perform_enqueued_jobs(only: Backfill::CodeScanningAlertNumberFanoutJob) do
            Backfill::CodeScanningAlertNumberFanoutJob.perform_later(organization_ids: [@org.id, @org_2.id])
          end

          num_repos = CodeScanningAlertRevision.select(:repository_id).distinct.size
          assert_equal(3, num_repos)
          assert_enqueued_jobs(num_repos, only: Backfill::CodeScanningAlertNumberJob)
        end
      end
    end
  end
end
