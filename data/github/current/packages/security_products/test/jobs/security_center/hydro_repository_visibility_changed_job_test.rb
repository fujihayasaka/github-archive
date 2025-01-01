# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryVisibilityChangedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @org = create :organization
      @repo = create(:private_repository, owner: @org)
      @repo_config = create(:repository_security_center_config, repository: @repo, visibility: :public)
    end

    setup do
      @queue = SecurityCenter::HydroRepositoryVisibilityChangedJob.queue_name
      @schema = "github.repositories.v1.VisibilityChanged"

      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    end

    test "it updates the repo config's 'visibility' value" do
      message = {
        repository_id: @repo.id,
        new_visibility: @repo.visibility,
      }

      assert_max_query_count(10, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: @repo.id)
      assert actual
      assert_equal @repo.visibility, actual.visibility
    end

    test "it publishes event to SecurityFeatureRepoUpdate hydro topic" do
      message = {
        repository_id: @repo.id,
        new_visibility: @repo.visibility,
      }

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
      assert_hydro_published_partial(
        {
          repository: {
            id: @repo.id,
            organization_id: @repo.owner.id,
            visibility: @repo.visibility,
          },
          source_event: "repo.access",
        },
        schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
      )
    end

    context "when repository is unknown to security center" do
      test "it retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository_id: repo.id,
          new_visibility: repo.visibility,
        }

        HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).once

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        assert_no_enqueued_jobs(only: RepositoryReconciliationJob)
      end

      test "it queues reconciliation after all retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository_id: repo.id,
          new_visibility: repo.visibility,
        }

        HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never

        encoded = encode_hydro_message(message, schema: @schema)
        decoded = decode_hydro_message(encoded)
        perform_hydro_message_job_encoded_decoded(
          encoded, decoded,
          schema: @schema, queue: @queue,
          only: [HydroRepositoryVisibilityChangedJob],
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
          repository_id: repo.id,
          new_visibility: repo.visibility,
        }

        HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "when repository is user-owned" do
      context "on GHES", enterprise_only: true do
        test "it does not update if feature flag is disabled" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

          user = create(:user)
          repo = create(:public_repository, owner: user, force_user_owned: true)
          create(:repository_security_center_config, repository: repo, visibility: "public")

          message = {
            repository_id: repo.id,
            new_visibility: "private",
          }

          HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never
          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal "public", config.visibility # no change
          assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
        end

        test "it updates if feature flag is enabled" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

          user = create(:user)
          repo = create(:public_repository, owner: user, force_user_owned: true)
          create(:repository_security_center_config, repository: repo, visibility: "public")

          message = {
            repository_id: repo.id,
            new_visibility: "private",
          }

          HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never
          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal "private", config.visibility # changed
        end
      end

      context "on non-GHES", skip_enterprise: true do
        test "it does not update for non-EMU user-owned repositories" do
          user = create(:user)
          repo = create(:public_repository, owner: user, force_user_owned: true)
          create(:repository_security_center_config, repository: repo, visibility: "public")

          message = {
            repository_id: repo.id,
            new_visibility: "private",
          }

          HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never
          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal "public", config.visibility # no change
          assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
        end

        test "it updates for EMU-owned repository if feature flag is enabled" do
          emu = create(:emu)
          repo = create(:public_repository, owner: emu, force_user_owned: true)
          create(:repository_security_center_config, repository: repo, visibility: "public")

          message = {
            repository_id: repo.id,
            new_visibility: "private",
          }

          HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never
          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal "private", config.visibility # no change
        end
      end
    end

    context "when feature is not available for owner" do
      test "it still updates" do
        repo = create(:repository, owner: create(:free_organization))
        create(:repository_security_center_config, repository: repo, visibility: "private")
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

        # Even though security center is not available, we still want to update the config record
        # for the sake of any features outside of security center that may rely on this information in our tables.
        refute SecurityFeatures.security_center_available?(repo.owner) unless GitHub.enterprise?

        message = {
          repository_id: repo.id,
          new_visibility: "public",
        }

        HydroRepositoryVisibilityChangedJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal message[:new_visibility], actual.visibility
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:private_repository, owner: @org)
        create(:repository_security_center_config, repository: repo, visibility: :public)

        message = {
          repository_id: repo.id,
          new_visibility: repo.visibility,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{@schema}"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:archived_repository, owner: @org)
        create(:repository_security_center_config, repository: repo, archived: false)

        message = {
          repository_id: repo.id,
          new_visibility: repo.visibility,
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
