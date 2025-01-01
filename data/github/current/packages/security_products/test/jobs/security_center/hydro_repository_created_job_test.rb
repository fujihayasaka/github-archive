# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroRepositoryCreatedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @user = create :user
      @business = create :business
      @org = create :business_plus_organization, admin: @user, business: @business
    end

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      @queue = HydroRepositoryCreatedJob.queue_name
      @schema = "github.repositories.v1.Created"
    end

    context "it creates a database record" do
      test "for an org owned by a business" do
        repo = create(:repository, owner: @org)
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert_equal repo.id, config.repository_id
        assert_equal repo.owner_id, config.owner_id
        assert_equal @business.id, config.business_id
        assert_equal "ORGANIZATION", config.owner_type
        assert_equal repo.name, config.name
        assert_equal repo.visibility, config.visibility
        assert_equal repo.archived?, config.archived
        refute config.ghas_enabled
      end

      test "for an org without a business", skip_enterprise: true do
        org = create :organization, admin: @user
        repo = create(:repository, owner: org)
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
        assert_equal repo.id, config.repository_id
        assert_equal repo.owner_id, config.owner_id
        assert_nil config.business_id
        assert_equal "ORGANIZATION", config.owner_type
        assert_equal repo.name, config.name
        assert_equal repo.visibility, config.visibility
        assert_equal repo.archived?, config.archived
        refute config.ghas_enabled
      end

      context "on non-GHES", skip_enterprise: true do
        test "does not create record for non-EMU user-owned repo" do
          user = create(:user)
          repo = create(:repository, owner: user, force_user_owned: true)
          message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
          assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])

          refute_hydro_messages(schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
        end

        test "creates a record for an EMU-owned repo" do
          emu = create(:emu)
          biz = emu.enterprise_managed_business
          repo = create(:private_repository, force_user_owned: true, owner: emu)
          message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal repo.id, config.repository_id
          assert_equal repo.owner_id, config.owner_id
          assert_equal biz.id, config.business_id
          assert_equal "USER", config.owner_type
          assert_equal repo.name, config.name
          assert_equal repo.visibility, config.visibility
          assert_equal repo.archived?, config.archived
          refute config.ghas_enabled
        end
      end

      context "on GHES", enterprise_only: true do
        test "creates a record for user-owned repos on GHES" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

          user = create(:user)
          repo = create(:private_repository, force_user_owned: true, owner: user)
          biz = GitHub.global_business

          message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          config = RepositorySecurityCenterConfig.find_by!(repository_id: repo.id)
          assert_equal repo.id, config.repository_id
          assert_equal repo.owner_id, config.owner_id
          assert_equal biz.id, config.business_id
          assert_equal "USER", config.owner_type
          assert_equal repo.name, config.name
          assert_equal repo.visibility, config.visibility
          assert_equal repo.archived?, config.archived
          refute config.ghas_enabled
        end

        test "does not create record for user-owned repo without feature flag" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

          user = create(:user)
          repo = create(:repository, owner: user, force_user_owned: true)
          message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
          assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_eligible"])

          refute_hydro_messages(schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
        end
      end
    end

    test "it publishes create event to SecurityFeatureRepoUpdate hydro topic" do
      repo = create(:repository, owner: @org)
      message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
      assert_hydro_published_partial(
        {
          repository: {
            id: repo.id,
            organization_id: repo.owner.id,
            visibility: repo.visibility,
          },
          source_event: @schema,
        },
        schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
      )
    end

    context "when repository is soft-deleted" do
      test "it does not create record" do
        repo = create(:repository, :soft_deleted, owner: @org)
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])

        refute_hydro_messages(schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
      end
    end

    context "when feature is not available for owner" do
      test "it still creates record" do
        repo = create(:repository, owner: create(:free_organization))
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)
        refute RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

        # Even though security center is not available, we still create the record because
        # Dependabot alerts org and biz level APIs rely on our tables to determine org->repo relationships.
        refute SecurityFeatures.security_center_available?(repo.owner) unless GitHub.enterprise?

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert RepositorySecurityCenterConfig.find_by(repository_id: repo.id)

        assert_hydro_messages(count: 1, schema: "github.security_center.v1.SecurityFeatureRepoUpdate")
        assert_hydro_published_partial(
          {
            repository: {
              id: repo.id,
              organization_id: repo.owner.id,
              visibility: repo.visibility,
            },
            source_event: @schema,
          },
          schema: "github.security_center.v1.SecurityFeatureRepoUpdate"
        )
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: @org)
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["topic:github.repositories.v1.Created"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)
        message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repo)

        assert_raises(StandardError) do
          RepositorySecurityCenterConfig.stubs(:upsert).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end

    context "resiliency" do
      test "it retries on recoverable errors" do
        repo = create(:repository, owner: @org)

        message = {
          repository_id: repo.id
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          SecurityCenterUpdater.stubs(:notify_security_center_for_repo).raises(exception, "boom")
          RepositorySecurityCenterConfig.stubs(:throttle_writes).raises(exception, "boom")
          HydroRepositoryCreatedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: @org)

        message = {
          repository_id: repo.id
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          SecurityCenterUpdater.stubs(:notify_security_center_for_repo).raises(exception)
          RepositorySecurityCenterConfig.stubs(:throttle_writes).raises(exception)
          HydroRepositoryCreatedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries when repo not found" do
        ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
        HydroRepositoryCreatedJob.any_instance.expects(:retry).once

        message = {
          repository_id: -1
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
