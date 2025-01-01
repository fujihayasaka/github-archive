# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroPushProtectionFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    setup do
      GitHub.global_business || create(:business)
      @queue = HydroPushProtectionFeatureToggledJob.queue_name
      @schema = "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled"

      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
    end

    test "it updates feature data" do
      repo = create(:repository, owner: create(:organization))

      Repository.any_instance.expects(:push_protection_security_center_status)
        .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
        .once

      message = {
        repository_id: repo.id,
        feature_enabled: true,
      }

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
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

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "for non-GHES, when repository is user-owned", skip_enterprise: true do
      test "it does not update for non-EMU" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
      end

      test "it updates feature data for an EMU" do
        emu = create(:emu)
        repo = create(:private_repository, force_user_owned: true, owner: emu)

        Repository.any_instance.expects(:push_protection_security_center_status)
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          .once

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
        assert db_status
        assert_equal "enrolled", db_status&.scanning_status
      end
    end

    context "for GHES, when repository is user-owned", enterprise_only: true do
      test "it updates feature data" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)

        Repository.any_instance.expects(:push_protection_security_center_status)
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          .once

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
        assert db_status
        assert_equal "enrolled", db_status&.scanning_status
      end

      test "does nothing when feature flag is disabled" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

        user = create(:user)
        repo = create(:private_repository, force_user_owned: true, owner: user)
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])
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

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning_push_protection")
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
          HydroPushProtectionFeatureToggledJob.any_instance.expects(:retry).once
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
          HydroPushProtectionFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries when repo not found" do
        ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
        HydroPushProtectionFeatureToggledJob.any_instance.expects(:retry).once

        message = {
          repository_id: -1,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
