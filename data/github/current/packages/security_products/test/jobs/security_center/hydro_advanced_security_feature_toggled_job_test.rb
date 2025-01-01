# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroAdvancedSecurityFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @business = GitHub.global_business || create(:business)
      @org = create :organization
      @repo = create(:repository, owner: @org)
      @repo_config = create(:repository_security_center_config, repository: @repo, ghas_enabled: false)
    end

    setup do
      Spokesd.enable_spokesd
      @queue = HydroAdvancedSecurityFeatureToggledJob.queue_name
      @schema = "github.security_center.v0.AdvancedSecurityToggled"

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    end

    test "it updates the repo config's 'ghas_enabled' value" do
      message = {
        repository_id: @repo_config.repository_id,
        feature_enabled: true,
      }

      expected_query_count = TestEnv.enterprise? ? 10 : 9
      assert_query_count(expected_query_count, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: @repo.id)
      assert actual
      assert_equal message[:feature_enabled], actual.ghas_enabled
    end

    test "it updates the repo config's 'business_id' value if mismatched", skip_enterprise: true do
      business = create(:business)
      org = create(:organization, business: business)
      repo = create(:repository, owner: org)

      # Here we force the repo config to point to @org
      repo_config = create(:repository_security_center_config,
        repository: repo, ghas_enabled: false,
        owner: @org, owner_type: "Organization",
        business_id: @org.business&.id,
      )

      message = {
        repository_id: repo_config.repository_id,
        feature_enabled: true,
      }

      expected_query_count = TestEnv.enterprise? ? 10 : 9
      assert_query_count(expected_query_count, ignore_feature_flags: true) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
      assert actual
      assert_equal message[:feature_enabled], actual.ghas_enabled
      assert_equal business.id, actual.business_id
    end

    context "SecurityFeatureRepoUpdate publish" do
      context "for an org-owned repository" do
        test "it publishes the event" do
          message = {
            repository_id: @repo.id,
            feature_enabled: true,
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
              source_event: "#{@schema}#enable",
            },
            schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
          )
        end
      end

      context "for a user-owned repository" do
        test "it does not publish the event" do
          user = create(:user)
          repo = create(:repository, owner: user, force_user_owned: true)

          message = {
            repository_id: repo.id,
            feature_enabled: true,
          }

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          refute_hydro_messages(schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
        end
      end

      context "for an emu-owned repository", skip_enterprise: true do
        test "it does not publish the event" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

          emu = create(:emu)
          repo = create(:private_repository, force_user_owned: true, owner: emu)
          create(:repository_security_center_config, repository: repo)

          message = {
            repository_id: repo.id,
            feature_enabled: true,
          }

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          refute_hydro_messages(schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
        end
      end
    end

    context "when repository is unknown to security center" do
      test "it retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).once

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        assert_no_enqueued_jobs(only: RepositoryReconciliationJob)
      end

      test "it queues reconciliation after all retries" do
        repo = create(:private_repository, owner: @org)
        # no RepositorySecurityCenterConfig record

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).never

        encoded = encode_hydro_message(message, schema: @schema)
        decoded = decode_hydro_message(encoded)
        perform_hydro_message_job_encoded_decoded(
          encoded, decoded,
          schema: @schema, queue: @queue,
          only: [HydroAdvancedSecurityFeatureToggledJob],
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
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "on non-GHES, when repository is user-owned", skip_enterprise: true do
      test "it does not update for a non-EMU" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end

      test "it updates 'ghas_enabled' for an EMU repo" do
        emu = create(:emu)
        repo = create(:private_repository, force_user_owned: true, owner: emu)
        create(:repository_security_center_config, repository: repo)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        assert_query_count(5, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal message[:feature_enabled], actual.ghas_enabled
      end
    end

    context "on GHES, when repository is user-owned", enterprise_only: true do
      test "it updates 'ghas_enabled'" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)
        create(:repository_security_center_config, repository: repo)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        query_count = GitHub.enterprise? ? 4 : 3
        assert_query_count(query_count, ignore_feature_flags: true) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal message[:feature_enabled], actual.ghas_enabled
      end

      test "does nothing if feature flag is disabled" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end
    end

    context "when feature is not available for owner" do
      test "it still updates" do
        repo = create(:repository, owner: create(:free_organization))
        create(:repository_security_center_config, repository: repo, ghas_enabled: false)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

        # Even though security center is not available, we still want to update the config record
        # for the sake of any features outside of security center that may rely on this information in our tables.
        refute SecurityFeatures.security_center_available?(repo.owner) unless GitHub.enterprise?

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        HydroAdvancedSecurityFeatureToggledJob.any_instance.expects(:retry).never

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        actual = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert actual
        assert_equal message[:feature_enabled], actual.ghas_enabled
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        message = {
          repository_id: @repo_config.repository_id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{@schema}#enable"])
      end

      test "does not report telemetry when job fails" do
        message = {
          repository_id: @repo_config.repository_id,
          feature_enabled: true,
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
