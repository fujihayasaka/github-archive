# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryTransferredJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @org_1 = create :business_plus_organization
      @org_2 = create :organization
      @user_1 = create :user
      @user_2 = create :user

      unless GitHub.enterprise?
        @emu_1 = create :emu
        @emu_2 = create :emu, business: @emu_1.enterprise_managed_business
      end
    end

    setup do
      @queue = HydroRepositoryTransferredJob.queue_name
      @schema = "github.repositories.v1.Transferred"

      @org_1.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
      @emu_1.enterprise_managed_business.mark_advanced_security_as_purchased_for_entity(actor: User.ghost) unless GitHub.enterprise?
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
    end

    test "it enqueues repository sync job" do
      repository = create(:repository, owner: @org_1)

      message = new_message(repository:, previous_owner: @org_2)

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

    context "user-owned repositories" do
      context "on GHES", enterprise_only: true do
        # EMUs do not exist on GHES, but we treat GHES users as if they were EMUs for purposes of extending GHAS features
        test "when new owner is a User, it enqueues repository sync job" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)
          build_perform_assert_repository_sync_job(@user_1, @org_2)
        end

        test "when old owner is a User, it enqueues repository sync job" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)
          build_perform_assert_repository_sync_job(@org_1, @user_1)
        end

        test "when both owners are Users, it enqueues repository sync job" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)
          build_perform_assert_repository_sync_job(@user_1, @user_2)
        end

        test "does nothing when feature flag is disabled" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)
          build_perform_assert_repository_sync_job(@user_1, @user_2, job_expected: false)
        end
      end

      context "on non-GHES", skip_enterprise: true do
        test "when new owner is an EMU account, it enqueues repository sync job" do
          build_perform_assert_repository_sync_job(@emu_1, @org_2)
        end

        test "when old owner is an EMU account, it enqueues repository sync job" do
          build_perform_assert_repository_sync_job(@org_1, @emu_1)
        end

        test "when both are EMU accounts, it enqueues repository sync job" do
          build_perform_assert_repository_sync_job(@emu_1, @emu_2)
        end

        test "when both are non-EMU User accounts, it does not enqueue repository sync job" do
          build_perform_assert_repository_sync_job(@user_1, @user_2, job_expected: false)
        end
      end
    end

    test "it publishes event to SecurityFeatureRepoUpdate hydro topic" do
      repository = create(:repository, owner: @org_1)

      message = new_message(repository:, previous_owner: @user_1)

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
      assert_hydro_published_partial(
        {
          repository: {
            id: repository.id,
            organization_id: repository.owner.id,
            visibility: repository.visibility,
          },
          source_event: "repo.transfer",
        },
        schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
      )
    end

    context "lifecycle telemetry" do
      test "does not report telemetry" do
        repository = create(:private_repository, owner: @org_1)

        message = new_message(repository:, previous_owner: @org_2)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end

    private

    def new_message(repository:, previous_owner:, new_name: nil, new_visibility: nil)
      {
        repository_id: repository.id,
        new_name: new_name || repository.name,
        new_visibility: new_visibility || repository.visibility,
        new_owner: {
          id: repository.owner_id
        },
        previous_owner: {
          id: previous_owner.id
        }
      }
    end

    def build_perform_assert_repository_sync_job(new_owner, old_owner, job_expected: true)
      repo = create(:private_repository, force_user_owned: true, owner: new_owner)

      message = new_message(repository: repo, previous_owner: old_owner)

      timestamp = Time.now.utc
      Timecop.freeze(timestamp) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      if job_expected
        assert_enqueued_jobs(1, only: RepositorySyncJob)
        assert_enqueued_with(job: RepositorySyncJob, args: [{
          repository_id: repo.id,
          source_event: @schema,
          event_timestamp: timestamp.to_i,
        }])
      else
        assert_no_enqueued_jobs(only: RepositorySyncJob)
      end
    end
  end
end
