# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class HydroRepositoryUnarchivedJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include GitHub::LoggerHelper
    include SecurityProductsEnablement::EnterpriseTestHelpers

    setup do
      @owner = create :organization
      @created_by_user = create(:user)
      @archived_repo = create(:archived_repository, owner: @owner, name: "archived-repo", created_by_user_id: @created_by_user.id)
      @unarchived_repo = create(:private_repository, owner: @owner, name: "unarchived-repo", created_by_user_id: @created_by_user.id)
    end

    def publish_and_perform(repo)
      perform_hydro_message_job(
        { repository_id: repo.id, actor_id: repo.created_by_user.id, request_id: SecureRandom.uuid },
        schema: "github.repositories.v1.Unarchived",
        queue: SecurityProductsEnablement::HydroRepositoryUnarchivedJob.queue_name
      )
    end

    context "skipping" do
      test "it skips repositories that are archived" do
        assert_logged(reason: :repository_archived) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(@archived_repo)
          end
        end
      end

      test "it skips repositories that are owned by users" do
        user = create(:user)
        repo = create(:repository, owner: user, created_by_user_id: user.id)
        assert repo.owner.user?

        create(:repository_security_configuration, repository: repo, user: @owner, state: :attached)

        assert_logged(reason: :repository_owner_is_user) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips repositories without repository security configuration" do
        assert_logged(reason: :repository_security_configuration_missing) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(@unarchived_repo)
          end
        end
      end

      [:removed, :removed_by_enterprise, :attaching, :updating, :detached].each do |state|
        test "it skips repositories with repository security configuration in #{state} state" do
          create(:repository_security_configuration, repository: @unarchived_repo, user: @owner, state: :removed)

          assert_logged(reason: :repository_security_configuration_ineligible) do
            assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
              publish_and_perform(@unarchived_repo)
            end
          end
        end
      end
    end

    test "enqueues a ApplySecurityConfigurationToRepositoryJob" do
      repo_config = create(:repository_security_configuration, repository: @unarchived_repo, user: @owner, state: :attached)

      publish_and_perform(@unarchived_repo)

      expected_args = {
        actor_id: @unarchived_repo.created_by_user.id,
        repository_id: @unarchived_repo.id,
        security_configuration_id: repo_config.security_configuration_id,
        override_params: {},
        reason: :repo_unarchived,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    [:attached, :enforced, :failed].each do |state|
      test "attaches GHR configuration to an unarchived repo with #{state} config state", skip_enterprise: true do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

        security_configuration = SecurityConfiguration.github_recommended_configuration
        repo_config = create(:repository_security_configuration, repository: @unarchived_repo, user: @owner, security_configuration:, state:)
        if state == :enforced
          create(:security_configuration_policy, :enforced, security_configuration:, target: @owner)
        end

        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
          publish_and_perform(@unarchived_repo)
        end

        repo_config = RepositorySecurityConfiguration.where(repository_id: @unarchived_repo.id).first!

        expected_state = state == :enforced ? "enforced" : "attached"
        assert_equal expected_state, repo_config.state
      end
    end

    [:attached, :enforced, :failed].each do |state|
      test "attaches a configuration to an unarchived repo with #{state} config state", skip_enterprise: true do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

        if GitHub.enterprise?
          GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        end

        security_configuration = create :security_configuration, target: @owner
        create :repository_security_configuration, repository: @unarchived_repo, user: @owner, security_configuration:, state: state
        if state == :enforced
          create(:security_configuration_policy, :enforced, security_configuration:, target: @owner)
        end

        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
          publish_and_perform(@unarchived_repo)
        end

        repo_config = RepositorySecurityConfiguration.where(repository_id: @unarchived_repo.id).first!

        expected_state = state == :enforced ? "enforced" : "attached"
        assert_equal expected_state, repo_config.state
      end
    end

    [:attached, :enforced, :failed].each do |state|
      test "attaches a configuration to an unarchived repo with #{state} config state", enterprise_only: true do
        user = create(:user)
        business = create(:global_business) || create(:business, owners: [user])
        owner = create(:business_plus_organization, business: business, admin: user)

        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        GitHub.stubs(:actions_enabled?).returns(true)
        CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
        CodeScanning::Status.stubs(:validate_prerequisites)
        CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

        security_configuration = create :security_configuration, target: @owner
        create :repository_security_configuration, repository: @unarchived_repo, user: @owner, security_configuration:, state: state
        if state == :enforced
          create(:security_configuration_policy, :enforced, security_configuration:, target: @owner)
        end

        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
          publish_and_perform(@unarchived_repo)
        end

        repo_config = RepositorySecurityConfiguration.where(repository_id: @unarchived_repo.id).first!
        expected_state = state == :enforced ? "enforced" : "attached"
        assert_equal expected_state, repo_config.state
      end
    end
  end
end
