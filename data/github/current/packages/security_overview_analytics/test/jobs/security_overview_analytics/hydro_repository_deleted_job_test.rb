# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryDeletedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @queue = HydroRepositoryDeletedJob.queue_name
      @schema = "github.repositories.v1.Deleted"
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
      @soa_repo = create(:soa_repository, repository: @repo)
      @soa_repo_summary = create(:soa_feature_status, repository_metadata: @soa_repo)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(true)
    end

    context "#perform" do
      test "can delete data on repo deletion" do
        assert Repository.find_by(repository_id: @repo.id)
        assert FeatureStatus.find_by(repository_id: @repo.id)

        assert_query_counts(3) do
          perform_hydro_message_job({
            repository_id: @repo.id
          }, schema: @schema, queue: @queue)
        end

        refute Repository.find_by(repository_id: @repo.id)
        refute FeatureStatus.find_by(repository_id: @repo.id)
      end

      test "does nothing if repository owner validation fails" do
        TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(false)
        assert Repository.find_by(repository_id: @repo.id)
        assert FeatureStatus.find_by(repository_id: @repo.id)

        assert_query_counts(1) do
          perform_hydro_message_job({
            repository_id: @repo.id
          }, schema: @schema, queue: @queue)
        end

        assert Repository.find_by(repository_id: @repo.id)
        assert FeatureStatus.find_by(repository_id: @repo.id)
      end

      test "does not throw if a record with the same repository id does not exist" do
        repo_id = @soa_repo.repository_id
        @soa_repo.destroy!
        @soa_repo_summary.destroy!
        refute Repository.find_by(repository_id: repo_id)
        refute FeatureStatus.find_by(repository_id: repo_id)

        assert_query_counts(3) do
          assert_nothing_raised do
            perform_hydro_message_job({
              repository_id: repo_id
            }, schema: @schema, queue: @queue)
          end
        end

        refute Repository.find_by(repository_id: repo_id)
        refute FeatureStatus.find_by(repository_id: repo_id)
      end
    end
  end
end
