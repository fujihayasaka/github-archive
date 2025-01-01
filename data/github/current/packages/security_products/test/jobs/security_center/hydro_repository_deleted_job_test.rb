# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryDeletedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @user = create :user
      @org = create :organization, admin: @user
      @repo = create(:repository, owner: @org)

      @config = create(:repository_security_center_config, repository: @repo)
      @status = create(:repository_security_center_status, repository: @repo, feature_type: :dependabot_alerts, scanning_status: :enrolled)
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = HydroRepositoryDeletedJob.queue_name
      @schema = "github.repositories.v1.Deleted"
    end

    test "it publishes delete event to SecurityFeatureRepoUpdate hydro topic" do
      orchestration = RepositoryOrchestration.delete(@repo, actor: User.ghost)

      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)
      assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
    end

    test "it deletes database records" do
      orchestration = RepositoryOrchestration.delete(@repo, actor: User.ghost)

      assert RepositorySecurityCenterConfig.exists?(@config.id)
      assert RepositorySecurityCenterStatus.exists?(@status.id)

      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)

      refute RepositorySecurityCenterConfig.exists?(@config.id)
      refute RepositorySecurityCenterStatus.exists?(@status.id)
    end

    test "it does not fail for repository without security center data" do
      repo = create(:repository, owner: @org)
      orchestration = RepositoryOrchestration.delete(repo, actor: User.ghost)

      assert_empty RepositorySecurityCenterConfig.where(repository_id: repo.id).to_a
      assert_empty RepositorySecurityCenterStatus.where(repository_id: repo.id).to_a

      perform_hydro_message_job(orchestration.class.build_hydro_event_message(repo.id), schema: @schema, queue: @queue)

      assert_empty RepositorySecurityCenterConfig.where(repository_id: repo.id).to_a
      assert_empty RepositorySecurityCenterStatus.where(repository_id: repo.id).to_a
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: @org)

        message = {
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["topic:github.repositories.v1.Deleted"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)

        message = {
          repository_id: repo.id,
        }

        assert_raises(StandardError) do
          RepositorySecurityCenterConfig.stubs(:throttle).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end
  end
end
