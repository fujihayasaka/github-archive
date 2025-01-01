# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class RepositoryDataCompressionJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @org = create(:business_plus_organization)
    end

    setup do
      Initialization.any_instance.stubs(:any_initialized?).returns(true)
      @features = %w[dependabot code_scanning secret_scanning feature_status]
      @repo1 = create(:repository, owner: @org).tap do |r|
        metadata = create(:soa_repository, repository: r)
      end
    end

    context "#perform" do
      context "tenant validation" do
        test "does not call alert-level job if org fails tenant validation" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          AlertDataCompressionJob.expects(:perform_later).never

          assert_performed_jobs 1, only: RepositoryDataCompressionJob do
            RepositoryDataCompressionJob.perform_later
          end
        end
      end

      test "calls AlertDataCompressionJob for each feature provided" do
        AlertDataCompressionJob.expects(:perform_later).with(feature: "dependabot", repository_id: @repo1.id, owner_id: @org.id, dry_run: false).once
        AlertDataCompressionJob.expects(:perform_later).with(feature: "code_scanning", repository_id: @repo1.id, owner_id: @org.id, dry_run: false).once
        AlertDataCompressionJob.expects(:perform_later).with(feature: "secret_scanning", repository_id: @repo1.id, owner_id: @org.id, dry_run: false).once
        FeatureStatusDataCompressionJob.expects(:perform_later).with(repository_id: @repo1.id, owner_id: @org.id, dry_run: false).once

        assert_performed_jobs 1, only: RepositoryDataCompressionJob do
          RepositoryDataCompressionJob.perform_later
        end
      end

      test "calls alert-level job for each repo across all orgs provided" do
        org2 = create(:business_plus_organization)
        repo2 = create(:repository, owner: org2).tap do |r|
          metadata = create(:soa_repository, repository: r)
        end

        # each repo gets called 3 times, once for each alert feature
        AlertDataCompressionJob.expects(:perform_later).with do |kwargs|
          kwargs[:repository_id] == @repo1.id
          kwargs[:owner_id] == @org.id
        end.times(3)
        AlertDataCompressionJob.expects(:perform_later).with do |kwargs|
          kwargs[:repository_id] == repo2.id
          kwargs[:owner_id] == org2.id
        end.times(3)
        # One feature_status job for each repo
        FeatureStatusDataCompressionJob.expects(:perform_later).with do |kwargs|
          kwargs[:repository_id] == repo2.id
          kwargs[:owner_id] == org2.id
        end.times(1)
        FeatureStatusDataCompressionJob.expects(:perform_later).with do |kwargs|
          kwargs[:repository_id] == @repo1.id
          kwargs[:owner_id] == @org.id
        end.times(1)

        assert_performed_jobs 1, only: RepositoryDataCompressionJob do
          RepositoryDataCompressionJob.perform_later
        end
      end
    end

    context "batched job" do
      test "queues subsequent jobs for batching" do
        org = create(:organization).tap do |o|
          8.times do
            create(:repository, owner: o).tap do |r|
              create(:soa_repository, repository: r)
            end
          end
        end

        RepositoryDataCompressionJob.stub_const(:BATCH_SIZE, 5) do
          assert_performed_jobs 2, only: RepositoryDataCompressionJob do
            perform_enqueued_jobs only: RepositoryDataCompressionJob do
              RepositoryDataCompressionJob.perform_later
            end
          end
        end

        assert_dogstats_distribution 1, "batched_job.total_time.dist"
      end
    end

    context "hash lock" do
      test "allows one job to be enqueued at a time" do
        assert_enqueued_jobs 1, only: RepositoryDataCompressionJob do
          RepositoryDataCompressionJob.perform_later
          RepositoryDataCompressionJob.perform_later
          RepositoryDataCompressionJob.perform_later
        end
      end
    end
  end
end
