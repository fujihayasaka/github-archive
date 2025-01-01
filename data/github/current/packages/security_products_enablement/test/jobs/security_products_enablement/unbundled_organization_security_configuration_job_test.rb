# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

module SecurityProductsEnablement
  class UnbundledOrganizationSecurityConfigurationJobTest < GitHub::TestCase
    include JobTestHelper
    include TurboghasHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers
    include SecurityProductsEnablementHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @user = create(:verified_user)
      @business = GitHub.enterprise? ? create(:global_business) : create(:business)
      @org = create(:organization, admin: @user, business: @business)

      @repo1 = create(:private_repository, owner: @org)
      @repo2 = create(:private_repository, owner: @org)
      @repo3 = create(:repository, owner: @org)
      @repo4 = create(:repository, owner: @org)
      @archived_repo = create(:archived_repository, owner: @org).tap { |repo| repo.update!(public: false) }
    end

    setup do
      @security_configuration = create(:unbundled_security_configuration, target: @org)
      setup_search
      make_searchable(@repo1, @repo2, @repo3, @repo4, @archived_repo)

      stub_auto_codeql
    end

    context "applying a configuration" do
      test "applies the configuration to repositories in the org" do
        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 5, only: ApplySecurityConfigurationToRepositoryJob
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              reason: nil,
            }]
          )
        end

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 5, job_progress_tracker.total_jobs
        assert_equal 5, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "applies the configuration to only repos without configuration in the org" do
        [@repo1, @repo3].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end

        assert_empty RepositorySecurityConfiguration.where(repository_id: [@repo2.id, @repo4.id, @archived_repo.id])

        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            repository_query: "configuration:None",
            override_existing_config: true,
          )

        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 3, only: ApplySecurityConfigurationToRepositoryJob
        [@repo2, @repo4, @archived_repo].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              reason: nil,
            }]
          )
        end

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 3, job_progress_tracker.total_jobs
        assert_equal 3, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo2.id, @repo4.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "applies to archived repos specified by repository_id" do
        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: [@repo1, @archived_repo.id],
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 2, only: ApplySecurityConfigurationToRepositoryJob
        assert_enqueued_with(
          job: ApplySecurityConfigurationToRepositoryJob,
          args: [{
            actor_id: @user.id,
            repository_id: @repo1.id,
            security_configuration_id: @security_configuration.id,
            override_params: { skip_backfill_request: "1" },
            reason: nil,
          }]
        )

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 2, job_progress_tracker.total_jobs
        assert_equal 2, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo1.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "applies the configuration and prevents additonal license usage when insufficent SP licenes" do
        setup_entity_as_volume_unbundled(@business)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        secret_protection = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::SecretSecurity)

        # stub for org job
        secret_protection.expects(:seat_usage_increase_if_enabled_for_repos).with(repository_ids).returns(20)

        # stub for repo jobs
        [@repo1, @repo2, @repo3, @repo4].each do |repository|
          if GitHub.enterprise? || repository.private?
            secret_protection.expects(:seat_usage_increase_if_enabled_for_repos).with([repository.id]).returns(5)
          else
            secret_protection.expects(:seat_usage_increase_if_enabled_for_repos).with([repository.id]).returns(0)
          end
        end

        Organization.any_instance.stubs(secret_protection:)

        refute @repo1.code_security_enabled?
        refute SecretScanning::Features::Repo::TokenScanning.new(@repo1).enabled?

        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: repository_ids,
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 4, only: ApplySecurityConfigurationToRepositoryJob
        [@repo1, @repo2, @repo3, @repo4].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              prevent_additional_sku_usage: [GitHub::Turboghas::SKU::SecretSecurity],
              reason: nil,
            }]
          )
        end

        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
        assert_performed_jobs 4, only: ApplySecurityConfigurationToRepositoryJob

        if GitHub.enterprise?
          private_repos = [@repo1, @repo2, @repo3, @repo4]
          public_repos = []
        else
          private_repos = [@repo1, @repo2]
          public_repos = [@repo3, @repo4]
        end

        private_repos.each do |repo|
          repo.reload
          assert repo.code_security_enabled?, "expected #{repo.name} to have code security enabled"
          refute SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
          assert_equal "failed", repo.repository_security_configuration.state
          assert_equal "Enabling secret scanning would exceed available licenses.", repo.repository_security_configuration.failure_reason
        end

        public_repos.each do |repo|
          repo.reload
          refute repo.code_security_enabled? # public repos don't enable the SKU
          assert repo.code_scanning_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
          assert_equal "attached", repo.repository_security_configuration.state
          assert_nil repo.repository_security_configuration.failure_reason
        end
      end

      test "applies the configuration and prevents additonal license usage when insufficent CS licenes" do
        setup_entity_as_volume_unbundled(@business)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        code_security = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::CodeSecurity)

        # stub for org job
        code_security.expects(:seat_usage_increase_if_enabled_for_repos).with(repository_ids).returns(20)

        # stub for repo jobs
        [@repo1, @repo2, @repo3, @repo4].each do |repository|
          code_security.expects(:seat_usage_increase_if_enabled_for_repos).with([repository.id]).returns(5) if GitHub.enterprise? || repository.private?
        end

        Organization.any_instance.stubs(code_security:)

        refute @repo1.code_security_enabled?
        refute SecretScanning::Features::Repo::TokenScanning.new(@repo1).enabled?

        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: repository_ids,
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 4, only: ApplySecurityConfigurationToRepositoryJob
        [@repo1, @repo2, @repo3, @repo4].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              prevent_additional_sku_usage: [GitHub::Turboghas::SKU::CodeSecurity],
              reason: nil,
            }]
          )
        end

        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
        assert_performed_jobs 4, only: ApplySecurityConfigurationToRepositoryJob

        if GitHub.enterprise?
          private_repos = [@repo1, @repo2, @repo3, @repo4]
          public_repos = []
        else
          private_repos = [@repo1, @repo2]
          public_repos = [@repo3, @repo4]
        end

        private_repos.each do |repo|
          repo.reload
          refute repo.code_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
          assert_equal "failed", repo.repository_security_configuration.state
          assert_equal "Enabling Code Security would exceed seat allowance.", repo.repository_security_configuration.failure_reason
        end

        public_repos.each do |repo|
          repo.reload
          assert repo.code_scanning_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
          assert_equal "attached", repo.repository_security_configuration.state
          assert_nil repo.repository_security_configuration.failure_reason
        end
      end
    end

    context "preventing license consumption" do
      context "on a metered account" do
        test "doesn't prevent licenses when bundled" do
          setup_entity_as_metered_bundled(@business)
          assert @business.advanced_security_purchased?

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "doesn't prevent licenses when unbundled" do
          setup_entity_as_metered_unbundled(@business)
          assert @business.secret_protection_purchased?
          assert @business.code_security_purchased?

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
        end
      end

      context "on a volume unbundled account" do
        test "doesn't prevent Secret Protection licenses when not purchased" do
          setup_business_as_volume_cs_only(@business)
          refute @business.secret_protection_purchased?

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "doesn't prevent Code Security licenses when not purchased" do
          setup_business_as_volume_sp_only(@business)
          refute @business.code_security_purchased?

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "prevents additional Secret Protection licenses when in overage" do
          setup_entity_as_volume_unbundled(@business)

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]

          secret_protection = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::SecretSecurity)
          secret_protection.expects(allowance_exceeded?: true)
          Organization.any_instance.stubs(secret_protection:)

          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new([GitHub::Turboghas::SKU::SecretSecurity]), job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "prevents additional Code Security licenses when in overage" do
          setup_entity_as_volume_unbundled(@business)

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]

          code_security = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::CodeSecurity)
          code_security.expects(allowance_exceeded?: true)
          Organization.any_instance.stubs(code_security:)

          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new([GitHub::Turboghas::SKU::CodeSecurity]), job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "prevents additional Secret Protection licenses when there aren't sufficent licenses" do
          setup_entity_as_volume_unbundled(@business)

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]

          secret_protection = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::SecretSecurity)
          secret_protection.expects(:seat_usage_increase_if_enabled_for_repos).with(repository_ids).returns(20)
          Organization.any_instance.stubs(secret_protection:)

          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new([GitHub::Turboghas::SKU::SecretSecurity]), job.prevent_additional_sku_usage(@org, repository_ids)
        end

        test "prevents additional Code Security licenses when there aren't sufficent licenses" do
          setup_entity_as_volume_unbundled(@business)

          repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]

          code_security = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::CodeSecurity)
          code_security.expects(:seat_usage_increase_if_enabled_for_repos).with(repository_ids).returns(10)
          Organization.any_instance.stubs(code_security:)

          job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

          assert_equal Set.new([GitHub::Turboghas::SKU::CodeSecurity]), job.prevent_additional_sku_usage(@org, repository_ids)
        end
      end
    end
  end
end
