# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryRestoredJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @org_1 = create :business_plus_organization
      @user_1 = create :user
    end

    setup do
      @queue = HydroRepositoryRestoredJob.queue_name
      @schema = "github.repositories.v2.Restored"

      @org_1.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
    end

    test "it enqueues repository sync job" do
      repository = create(:repository, owner: @org_1)

      message = new_message(repository:)

      timestamp = Time.now.utc
      Timecop.freeze(timestamp) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_enqueued_jobs(1, only: RepositorySyncJob)
      assert_enqueued_with(job: RepositorySyncJob, args: [{
        repository_id: repository.id,
        source_event: @schema,
        event_timestamp: timestamp.to_i,
      }])
    end

    context "on non-GHES when the repository is user owned", skip_enterprise: true do
      test "it does not enqueue repository sync job for non-EMU" do
        repository = create(:repository, owner: @user_1, force_user_owned: true)

        message = new_message(repository:)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_no_enqueued_jobs(only: RepositorySyncJob)
      end

      test "it enqueues repository sync job for an EMU" do
        emu = create(:emu)
        repo = create(:private_repository, force_user_owned: true, owner: emu)

        message = new_message(repository: repo)

        timestamp = Time.now.utc
        Timecop.freeze(timestamp) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        assert_enqueued_jobs(1, only: RepositorySyncJob)
        assert_enqueued_with(job: RepositorySyncJob, args: [{
          repository_id: repo.id,
          source_event: @schema,
          event_timestamp: timestamp.to_i,
        }])
      end
    end

    context "on GHES, when the repository is user owned", enterprise_only: true do
      test "it enqueues repository sync job" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        message = new_message(repository: repo)

        timestamp = Time.now.utc
        Timecop.freeze(timestamp) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        assert_enqueued_jobs(1, only: RepositorySyncJob)
        assert_enqueued_with(job: RepositorySyncJob, args: [{
          repository_id: repo.id,
          source_event: @schema,
          event_timestamp: timestamp.to_i,
        }])
      end

      test "does nothing when the feature flag is disabled" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        message = new_message(repository: repo)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_no_enqueued_jobs(only: RepositorySyncJob)
      end
    end

    test "it publishes event to SecurityFeatureRepoUpdate hydro topic" do
      repository = create(:repository, owner: @org_1)

      message = new_message(repository:)

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
      assert_hydro_published_partial(
        {
          repository: {
            id: repository.id,
            organization_id: repository.owner.id,
            visibility: repository.visibility,
          },
          source_event: "repo.restore",
        },
        schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
      )
    end

    context "lifecycle telemetry" do
      test "does not report telemetry" do
        repository = create(:repository, owner: @org_1)

        message = new_message(repository:)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end

    private

    def new_message(repository:)
      {
        repository_id: repository.id,
      }
    end
  end
end
