# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryRenamedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      GitHub.global_business || create(:business)
      @org = create :organization
      @repo = create(:repository, owner: @org, name: "updated-name")
      @repo_config = create(:repository_security_center_config, repository: @repo, name: "original-name", updated_at: 1.month.ago)
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = SecurityCenter::HydroRepositoryRenamedJob.queue_name
      @schema = "github.v1.RepositoryRename"

      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
    end

    test "it updates the repo config's 'name' value" do
      message = {
        repository: {
          id: @repo.id,
        },
        current_name: @repo.name,
      }

      assert_query_count(4, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: @repo.id)
      assert actual
      assert_equal @repo.name, actual.name
    end

    context "when repository is unknown to security center" do
      test "it retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository: {
            id: repo.id,
          },
          current_name: repo.name
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).once

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        assert_no_enqueued_jobs(only: RepositoryReconciliationJob)
      end

      test "it queues reconciliation after all retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository: {
            id: repo.id,
          },
          current_name: repo.name
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).never

        encoded = encode_hydro_message(message, schema: @schema)
        decoded = decode_hydro_message(encoded)
        perform_hydro_message_job_encoded_decoded(
          encoded, decoded,
          schema: @schema, queue: @queue,
          only: [HydroRepositoryRenamedJob],
          headers: { "retries" => { LifecycleEventHandler::RepositoryConfigNotFound.name => HydroMessageJob::DEFAULT_MAX_RETRIES }.to_json }
        )

        assert_enqueued_jobs(1, only: RepositoryReconciliationJob)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:missing_repo_config"])

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        perform_enqueued_jobs(only: RepositoryReconciliationJob)
        assert RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
      end
    end

    context "when repository is soft-deleted" do
      test "it does not update" do
        repo = create(:repository, :soft_deleted, owner: @org)

        message = {
          repository: {
            id: repo.id,
          },
          current_name: repo.name
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "on non-GHES, when the repository is user-owned", skip_enterprise: true do
      test "it does not update for non-EMU" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)

        message = {
          repository: {
            id: repo.id,
          },
          current_name: repo.name
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end

      test "it updates the repo config's 'name' value for an EMU" do
        emu = create(:emu)
        repo = create(:private_repository, force_user_owned: true, owner: emu)
        repo_config = create(:repository_security_center_config, repository: repo, archived: false)

        message = {
          repository: {
            id: repo.id,
          },
          current_name: "new repo name",
        }

        assert_query_count(6, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal "new repo name", actual.name
      end
    end

    context "on GHES, when the repository is user-owned", enterprise_only: true do
      test "it updates the repo config's 'name' value" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)
        repo_config = create(:repository_security_center_config, repository: repo, archived: false)

        message = {
          repository: {
            id: repo.id,
          },
          current_name: "new repo name",
        }

        assert_query_count(4, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal "new repo name", actual.name
      end

      test "it does not update when the feature flag is disabled" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        message = {
          repository: {
            id: repo.id,
          },
          current_name: "new repo name"
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end
    end

    context "when feature is not available for owner" do
      test "it does not update" do
        repo = create(:repository, owner: create(:free_organization))
        create(:repository_security_center_config, repository: repo, name: "original-name")
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

        # Even though security center is not available, we still want to update the config record
        # for the sake of any features outside of security center that may rely on this information in our tables.
        refute SecurityFeatures.security_center_available?(repo.owner) unless GitHub.enterprise?

        message = {
          repository: {
            id: repo.id,
          },
          current_name: "new-name",
        }

        HydroRepositoryRenamedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal message[:current_name], actual.name
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        message = {
          repository: {
            id: @repo.id,
          },
          current_name: @repo.name
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:github.v1.RepositoryRename"])
      end

      test "does not report telemetry when job fails" do
        message = {
          repository: {
            id: @repo.id,
          },
          current_name: @repo.name
        }

        assert_raises(StandardError) do
          RepositorySecurityCenterConfig.stubs(:throttle_writes).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end
  end
end
