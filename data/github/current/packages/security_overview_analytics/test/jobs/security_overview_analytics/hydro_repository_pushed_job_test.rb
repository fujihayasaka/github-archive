# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryPushedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @org = create :organization
    end

    setup do
      @queue = HydroRepositoryPushedJob.queue_name
      @schema = "github.repositories.v1.Pushed"

      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(true)
    end

    test "it updates the repository's 'pushed_at' value" do
      repo = create(:repository, owner: @org)
      create(:soa_repository, repository: repo, pushed_at: 1.year.ago, updated_at: 1.month.ago)

      message = {
        repository_id: repo.id,
        pushed_at: repo.pushed_at,
      }

      current_time = Time.now.utc
      Timecop.freeze(current_time) do
        assert_query_count(2, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      actual = SecurityOverviewAnalytics::Repository.find_by!(repository_id: repo.id)
      assert actual
      assert_equal repo.pushed_at, actual.pushed_at
      assert_equal current_time.to_i, actual.updated_at&.utc&.to_i
    end

    test "ignores unknown repositories" do
      repo = create(:repository, owner: @org)
      # no SOA::Repository record

      message = {
        repository_id: repo.id,
        pushed_at: repo.pushed_at,
      }

      assert_query_count(2, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      refute SecurityOverviewAnalytics::Repository.find_by(repository_id: repo.id)
    end

    test "does nothing if repository owner is not eligible for features" do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(false)

      repo = create(:repository, owner: @org)

      message = {
        repository_id: repo.id,
        pushed_at: repo.pushed_at,
      }

      assert_query_count(1, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_dogstats_increment("security_overview_analytics.event.repository_pushed.skipped", tags: ["reason:ineligible_owner"])
      refute_dogstats_distribution("security_overview_analytics.updated.dist")
    end

    test "does nothing if push is for a repo's wiki" do
      repo = create(:repository, owner: @org)

      message = {
        repository_id: repo.id,
        pushed_at: repo.pushed_at,
        path: "/data/repositories/7/nw/71/43/b3/32399/2138199.wiki.git",
      }

      assert_query_count(0, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_dogstats_increment("security_overview_analytics.event.repository_pushed.skipped", tags: ["reason:wiki"])
      refute_dogstats_distribution("security_overview_analytics.updated.dist")
    end

    test "handles nil pushed_at" do
      repo = create(:repository, owner: @org)
      create(:soa_repository, repository: repo, pushed_at: 1.year.ago, updated_at: 1.month.ago)

      message = {
        repository_id: repo.id,
        pushed_at: nil,
      }

      current_time = Time.now.utc
      Timecop.freeze(current_time) do
        assert_query_count(2, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      actual = SecurityOverviewAnalytics::Repository.find_by!(repository_id: repo.id)
      assert actual
      assert_nil actual.pushed_at
      assert_equal current_time.to_i, actual.updated_at&.utc&.to_i
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: @org)
        create(:soa_repository, repository: repo, pushed_at: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_overview_analytics.updated.dist", tags: ["source_event:#{@schema}"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)
        create(:soa_repository, repository: repo, pushed_at: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        assert_raises(StandardError) do
          SecurityOverviewAnalytics::Repository.stubs(:throttle_writes).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_overview_analytics.updated.dist")
      end

      test "does not report to failbot on timeout" do
        repo = create(:repository, owner: @org)
        create(:soa_repository, repository: repo, pushed_at: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        ActiveRecord::Relation.any_instance.stubs(:update_all).raises(Errno::ETIMEDOUT).once
        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute_dogstats_distribution("security_overview_analytics.updated.dist")
        assert_dogstats_increment(1, "security_overview_analytics.updated.error")
        Failbot.expects(:report).never
      end
    end
  end
end
