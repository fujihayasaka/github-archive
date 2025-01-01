# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroSecretScanningFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    setup do
      GitHub.global_business || create(:business)
      @queue = HydroSecretScanningFeatureToggledJob.queue_name
      @schema = "github.secret_scanning.v1.SecretScanningFeatureToggled"

      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)

      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
    end

    test "it updates feature data" do
      repo = create(:repository, owner: create(:organization))

      Repository.any_instance.expects(:secret_scanning_security_center_status)
        .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
        .once

      message = {
        repository_id: repo.id,
        feature_enabled: true,
      }

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
      assert db_status
      assert_equal "enrolled", db_status&.scanning_status
    end

    context "when repository is soft-deleted" do
      test "it does not update" do
        repo = create(:repository, :soft_deleted, owner: create(:user))
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "on GHES, when repository is user owned", enterprise_only: true do
      test "it updates feature data" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)

        Repository.any_instance.expects(:secret_scanning_security_center_status)
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          .once

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert db_status
        assert_equal "enrolled", db_status&.scanning_status
      end

      test "it does not update if the feature flag is disabled" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end
    end

    context "on non-GHES, when repository is user-owned", skip_enterprise: true do
      test "it does not update for non-EMU accounts" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end

      test "it updates feature data for EMU accounts" do
        emu = create(:emu)
        repo = create(:private_repository, force_user_owned: true, owner: emu)

        Repository.any_instance.expects(:secret_scanning_security_center_status)
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          .once

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert db_status
        assert_equal "enrolled", db_status&.scanning_status
      end
    end

    context "when feature is not available for owner" do
      test "it does not update" do
        repo = create(:repository, owner: create(:organization))
        Repository.any_instance.expects(:security_center_notify).never
        SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:feature_not_available"])
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{@schema}#enable"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        assert_raises(StandardError) do
          Repository.any_instance.stubs(:security_center_notify).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end

    context "resiliency" do
      test "it retries on recoverable errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
          HydroSecretScanningFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroSecretScanningFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries when repo not found" do
        ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
        HydroSecretScanningFeatureToggledJob.any_instance.expects(:retry).once

        message = {
          repository_id: -1,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
