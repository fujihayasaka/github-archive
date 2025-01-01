# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryPushedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include PushTestHelper
    Spokesd.share_spokesdb(self)

    fixtures do
      @org = create :organization
    end

    setup do
      @queue = HydroRepositoryPushedJob.queue_name
      @schema = "github.repositories.v1.Pushed"
    end

    test "it updates the repo config's 'last_push' value" do
      repo = create(:repository, owner: @org)
      create(:repository_security_center_config, repository: repo, last_push: 1.year.ago, updated_at: 1.month.ago)

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

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
      assert actual
      assert_equal repo.pushed_at, actual.last_push
      assert_equal current_time.to_i, actual.updated_at&.utc&.to_i
    end

    test "ignores unknown repositories" do
      repo = create(:repository, owner: @org)
      # no RepositorySecurityCenterConfig record

      message = {
        repository_id: repo.id,
        pushed_at: repo.pushed_at,
      }

      assert_query_count(2, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
    end

    test "handles nil pushed_at" do
      repo = create(:repository, owner: @org)
      create(:repository_security_center_config, repository: repo, last_push: 1.year.ago, updated_at: 1.month.ago)

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

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
      assert actual
      assert_nil actual.last_push
      assert_equal current_time.to_i, actual.updated_at&.utc&.to_i
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: @org)
        create(:repository_security_center_config, repository: repo, last_push: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{@schema}"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)
        create(:repository_security_center_config, repository: repo, last_push: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        assert_raises(StandardError) do
          RepositorySecurityCenterConfig.stubs(:throttle_writes).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end

      test "does not report to failbot on timeout" do
        repo = create(:repository, owner: @org)
        create(:repository_security_center_config, repository: repo, last_push: 1.year.ago, updated_at: 1.month.ago)

        message = {
          repository_id: repo.id,
          pushed_at: repo.pushed_at,
        }

        ActiveRecord::Relation.any_instance.stubs(:update_all).raises(Errno::ETIMEDOUT).once
        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute_dogstats_distribution("security_center.repository_updated.dist")
        assert_dogstats_increment(1, "security_center.repository_updated.error")
        Failbot.expects(:report).never
      end
    end

    context "dependabot config instrumentation" do
      test "triggers event for changed dependabot config" do
        Spokesd.enable_spokesd

        repo = create(:repository, owner: @org, from_example: :simple)
        received_event = T.let(false, T::Boolean)
        GlobalInstrumenter.subscribe "security_center.dependabot_config_change" do |_event|
          received_event = true
        end

        push_changes(repository: repo, changes: { path: ".github/dependabot.yml" }, perform_hydro_push_jobs: [HydroRepositoryPushedJob])

        assert received_event
      end

      test "retries spokes API throttling error" do
        Spokesd.enable_spokesd

        repo = create(:repository, owner: @org, from_example: :simple)
        received_event = T.let(false, T::Boolean)
        GlobalInstrumenter.subscribe "security_center.dependabot_config_change" do |_event|
          received_event = true
        end

        Repositories::RefUpdate.any_instance.stubs(:changed_files).raises(SpokesAPI::ResourceExhausted).then.returns([Repositories::Push::ChangedFile.new(path: ".github/dependabot.yml")])

        push_changes(repository: repo, changes: { path: ".github/dependabot.yml" }, perform_hydro_push_jobs: [HydroRepositoryPushedJob])
        assert received_event
      end

      test "Doesn't raise throttling error on the last retry" do
        Spokesd.enable_spokesd

        repo = create(:repository, owner: @org, from_example: :simple)
        received_event = T.let(false, T::Boolean)
        GlobalInstrumenter.subscribe "security_center.dependabot_config_change" do |_event|
          received_event = true
        end

        Repositories::RefUpdate.any_instance.stubs(:changed_files).raises(SpokesAPI::ResourceExhausted)

        # we should still run the rest of the job if the last retry encounters a spokes error
        HydroRepositoryPushedJob.any_instance.expects(:instrument_repository_updated)

        push_changes(repository: repo, changes: { path: ".github/dependabot.yml" }, perform_hydro_push_jobs: [HydroRepositoryPushedJob])
        refute received_event
      end
    end
  end
end
