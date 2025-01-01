# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

module SecurityProductsEnablement
  class EnterpriseSecurityConfigurationJobTest < GitHub::TestCase
    include JobTestHelper
    include TurboghasHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers

    setup do
      setup_search

      @user = create(:verified_user)
      @business = GitHub.enterprise? ? create(:global_business) : create(:business)

      unless GitHub.enterprise? # Enterprise doesn't support having multiple businesses
        @other_business = create(:business)
      end

      @org1 = create(:organization, admin: @user, business: @business)
      @org2 = create(:organization, admin: @user, business: @business)
      @org3 = create(:organization, admin: @user, business: @business)
      @org4 = create(:organization, admin: @user, business: @other_business)

      # Enterprise Security Configuration
      @security_configuration = create(:security_configuration, target: @business)

      @repo1 = create(:private_repository, owner: @org1)
      @repo2 = create(:private_repository, owner: @org1)
      @repo3 = create(:repository, owner: @org2)
      @repo4 = create(:repository, owner: @org2)

      @archived_repo = create(:archived_repository, owner: @org1).tap { |repo| repo.update!(public: false) }
      @deleted_repo = create(:deleted_repository, owner: @org1)

      @repo5 = create(:private_repository, owner: @org3)
      @repo6 = create(:private_repository, owner: @org4)

      make_searchable(@repo1, @repo2, @repo3, @repo4, @repo5, @repo6, @archived_repo)

      # Stubs necessary for GHAS checks:
      Business.any_instance.stubs(
        advanced_security_purchased?: true,
        advanced_security_seats_for_entity: 1_234
      )
      GitHub::Enterprise::LicenseMock.any_instance.stubs(advanced_security_seats: 1_234) if GitHub.enterprise?
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      AdvancedSecurityLicense.any_instance.stubs(:unlimited_seats?).returns(true)
    end

    context "applying a configuration" do
      test "applies the configuration to organizations in the enterprise" do
        EnterpriseSecurityConfigurationJob.perform_now(
          security_configuration_id: @security_configuration.id,
          enterprise_id: @business.id,
          actor_id: @user.id,
          action: :apply,
          override_existing_config: true,
          user_session_id: nil,
          options: {}
        )

        assert_enqueued_jobs 3, only: OrganizationSecurityConfigurationJob
        3.times { perform_enqueued_jobs(only: OrganizationSecurityConfigurationJob) }

        # Enqueues 6 jobs for the 6 applicable repositories in the enterprise
        assert_enqueued_jobs 6, only: ApplySecurityConfigurationToRepositoryJob
      end

      test "applies the configuration to organizations without a configuration in the enterprise" do
        org1_security_configuration = create(:security_configuration, target: @org1)
        org2_security_configuration = create(:security_configuration, target: @org2)

        create(:repository_security_configuration, state: :attached, repository: @repo1, security_configuration: org1_security_configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo2, security_configuration: org1_security_configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: org2_security_configuration)

        EnterpriseSecurityConfigurationJob.perform_now(
          security_configuration_id: @security_configuration.id,
          enterprise_id: @business.id,
          actor_id: @user.id,
          action: :apply,
          override_existing_config: false,
          user_session_id: nil,
          options: {}
        )

        assert_enqueued_jobs 3, only: OrganizationSecurityConfigurationJob
        3.times { perform_enqueued_jobs(only: OrganizationSecurityConfigurationJob) }

        # Enqueues 3 jobs for the 3 applicable repositories in the enterprise
        assert_enqueued_jobs 3, only: ApplySecurityConfigurationToRepositoryJob

        repo1_config = RepositorySecurityConfiguration.find_by(repository: @repo1)
        repo2_config = RepositorySecurityConfiguration.find_by(repository: @repo2)
        repo3_config = RepositorySecurityConfiguration.find_by(repository: @repo3)
        repo4_config = RepositorySecurityConfiguration.find_by(repository: @repo4)
        repo5_config = RepositorySecurityConfiguration.find_by(repository: @repo5)
        archived_repo_config = RepositorySecurityConfiguration.find_by(repository: @archived_repo)

        # The repos with a configuration should have been skipped
        assert_equal repo1_config&.security_configuration, org1_security_configuration
        assert_equal repo1_config&.state, "attached"

        assert_equal repo2_config&.security_configuration, org1_security_configuration
        assert_equal repo2_config&.state, "attached"

        assert_equal repo3_config&.security_configuration, org2_security_configuration
        assert_equal repo3_config&.state, "attached"

        # The job should be attaching the enterprise configuration to repos without a configuration
        [repo4_config, repo5_config, archived_repo_config].each do |repo_config|
          assert_equal repo_config&.security_configuration, @security_configuration
          assert_equal repo_config&.state, "attaching"
        end
      end
    end

    context "updating a configuration" do
      test "enqueues jobs to update repositories attached to the configuration" do
        create(:repository_security_configuration, state: :attached, repository: @repo1, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: @security_configuration)

        create(:repository_security_configuration, state: :removed, repository: @repo2, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: @security_configuration)

        assert_enqueued_jobs(3, only: OrganizationSecurityConfigurationJob) do
          EnterpriseSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            enterprise_id: @business.id,
            actor_id: @user.id,
            action: :update,
            override_existing_config: true,
            user_session_id: nil,
            options: {}
          )
        end

        3.times { perform_enqueued_jobs(only: OrganizationSecurityConfigurationJob) }
        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob)

        repo1_config = RepositorySecurityConfiguration.find_by(repository: @repo1)
        repo3_config = RepositorySecurityConfiguration.find_by(repository: @repo3)
        refute_nil repo1_config
        refute_nil repo3_config
        assert_predicate repo1_config, :updating?
        assert_predicate repo3_config, :updating?
      end
    end

    context "detaching a configuration" do
      test "removes the repository security configuration records" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end
        assert_equal 5, RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count

        EnterpriseSecurityConfigurationJob.perform_now(
          security_configuration_id: @security_configuration.id,
          enterprise_id: @business.id,
          actor_id: @user.id,
          action: :detach,
          override_existing_config: true,
          user_session_id: nil,
          options: {}
        )

        assert_enqueued_jobs 3, only: OrganizationSecurityConfigurationJob

        assert_changes -> { RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count }, from: 5, to: 0 do
          3.times { perform_enqueued_jobs(only: OrganizationSecurityConfigurationJob) }
        end

        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo1)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo2)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo3)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo4)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @archived_repo)
      end
    end

    context "retry conditions" do
      test "retries on dirty exit" do
        assert_retry_on_dirty_exit(
          job: EnterpriseSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            enterprise_id: @business.id,
            actor_id: @user.id,
            override_existing_config: false,
            user_session_id: nil,
            options: {}
          }]
        )
      end

      test "retries on recoverable exceptions" do
        assert_retry_on_recoverable_exceptions(
          job: EnterpriseSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            enterprise_id: @business.id,
            actor_id: @user.id,
            override_existing_config: false,
            user_session_id: nil,
            options: {}
          }]
        )
      end
    end

    def stub_autocodeql_methods
      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).at_least_once.returns(false)
    end
  end
end
