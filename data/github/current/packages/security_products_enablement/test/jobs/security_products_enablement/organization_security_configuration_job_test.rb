# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

module SecurityProductsEnablement
  class OrganizationSecurityConfigurationJobTest < GitHub::TestCase
    include JobTestHelper
    include TurboghasHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers
    include SecurityProductsEnablementHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @user = create(:verified_user)
      @business = GitHub.enterprise? ? create(:global_business) : create(:business)
      @org = create(:organization, admin: @user, business: @business)
      @org2 = create(:organization, admin: @user, business: @business)
      @repo1 = create(:private_repository, owner: @org)
      @repo2 = create(:private_repository, owner: @org)
      @repo3 = create(:repository, owner: @org)
      @repo4 = create(:repository, owner: @org)
      @archived_repo = create(:archived_repository, owner: @org).tap { |repo| repo.update!(public: false) }
      @deleted_repo = create(:deleted_repository, owner: @org)

      @non_enterprise_org = create(:organization, skip_enterprise_managed_organization: true, admin: @user)
    end

    setup do
      setup_search
      make_searchable(@repo1, @repo2, @repo3, @repo4, @archived_repo)
      setup_entity_as_bundled_ghas(@business)

      @security_configuration = GitHub.enterprise? ? create(:security_configuration, target: @org) : SecurityConfiguration.github_recommended_configuration
      @non_enterprise_security_configuration = create(:security_configuration, :not_set, target: @non_enterprise_org)

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

      test "applies the configuration to repositories in the org when actor is a bot" do
        bot = create :bot
        integration = create :integration, owner: bot
        installation = make_integration_installation(integration: integration, target: @org, permissions: { "organization_administration" => :write })

        OrganizationSecurityConfigurationJob.perform_now(
          security_configuration_id: @security_configuration.id,
          organization_id: @org.id,
          actor_id: bot.id,
          action: :apply,
          repository_ids: nil,
          repository_query: "visibility:public,private,internal",
          override_existing_config: true,
        )

        assert_enqueued_jobs 5, only: ApplySecurityConfigurationToRepositoryJob
      end

      test "applies the configuration to only private repositories in the org when actor is a bot" do
        bot = create :bot
        integration = create :integration, owner: bot
        installation = make_integration_installation(integration: integration, target: @org, permissions: { "organization_administration" => :write })

        OrganizationSecurityConfigurationJob.perform_now(
          security_configuration_id: @security_configuration.id,
          organization_id: @org.id,
          actor_id: bot.id,
          action: :apply,
          repository_ids: nil,
          repository_query: "visibility:private,internal",
          override_existing_config: true,
        )

        assert_enqueued_jobs 3, only: ApplySecurityConfigurationToRepositoryJob
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

      test "applies the configuration and prevents additonal license usage" do
        setup_entity_as_bundled_ghas(@business, seats: 1)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        advanced_security_license = AdvancedSecurityLicense.new(@org, sku: GitHub::Turboghas::SKU::Bundled)

        # # stub for org job
        advanced_security_license.expects(:seat_usage_increase_if_enabled_for_repos).with(repository_ids).returns(4)

        # # stub for repo jobs
        [@repo1, @repo2, @repo3, @repo4].each do |repository|
          if GitHub.enterprise? || repository.private?
            advanced_security_license.expects(:seat_usage_increase_if_enabled_for_repos).with([repository.id]).returns(1)
          end
        end

        Organization.any_instance.stubs(advanced_security_license:)

        refute @repo1.vulnerability_alerts_enabled?

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
              prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
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
          refute repo.advanced_security_enabled?
          assert repo.vulnerability_alerts_enabled?, "expected #{repo.name} to have vulnerability alerts enabled"
          refute SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?, "expected #{repo.name} to have token scanning disabled"
          assert_equal "failed", repo.repository_security_configuration.state
          assert_equal "Enabling advanced security would exceed seat allowance.", repo.repository_security_configuration.failure_reason
        end

        public_repos.each do |repo|
          repo.reload
          refute repo.advanced_security_enabled? # public repos don't enable the SKU
          assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
          assert repo.vulnerability_alerts_enabled?, "expected #{repo.name} to have vulnerability alerts enabled"
          assert_equal "attached", repo.repository_security_configuration.state
          assert_nil repo.repository_security_configuration.failure_reason
        end
      end

      test "only increments the jobs progress tracker when a job is enqueued" do
        [@repo1, @repo3].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo)
        end

        SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:increment_jobs).times(3)
        SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).never

        assert_enqueued_jobs(3, only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
          )
        end
      end

      test "marks the job progress tracker as finished if no jobs were enqueued" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo)
        end

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
          )
        end

        job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)
        refute_predicate job_progress_tracker, :in_progress?
      end

      test "applies the github recommended configuration to repositories based off of a search query" do
        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: true,
            repository_query: "visibility:private"
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        [@repo1, @repo2, @archived_repo].each do |repo|
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
        assert_same_elements [@repo1.id, @repo2.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "does not apply configurations based off of a search query if repository IDs are present" do
        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: [@repo2, @repo4], # Only 1 of these repos match the query below.
            override_existing_config: true,
            repository_query: "visibility:private" # This should be ignored!
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        [@repo2, @repo4].each do |repo|
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
        assert_equal 2, job_progress_tracker.total_jobs
        assert_equal 2, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo2.id, @repo4.id], job_progress_tracker.repository_ids
      end

      test "applies configs to repos under SAML-enabled business" do
        biz_provider = create :business_saml_provider, business: @business
        org_member_identity = create :external_identity, user: @user, provider: biz_provider

        freeze_time do
          session = create :user_session, user: @user
          create :external_identity_session, user_session: session, external_identity: org_member_identity

          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: true,
            repository_query: "visibility:private",
            user_session_id: session.id
          )

          [@repo1, @repo2].each do |repo|
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
        end
      end

      test "adds org ID to a list for the owning Business" do
        job = OrganizationSecurityConfigurationJob.new(
          security_configuration_id: @security_configuration.id,
          organization_id: @org.id,
          actor_id: @user.id,
          action: :apply,
          repository_ids: nil,
          override_existing_config: true,
        )
        job_progress_tracker = job.job_progress_tracker
        job_progress_tracker.start # Normally done when the job is enqueued.

        # Ensure that the org ID is affiliated w/ the business:
        assert job_progress_tracker.class.business_jobs_running?(@org.business.id)
        assert_predicate job_progress_tracker, :in_progress?

        # Pretend jobs actually ran and finished:
        assert job_progress_tracker.finish
        refute job_progress_tracker.class.business_jobs_running?(@org.business.id)
      end

      test "adds multiple org IDs to a list for the owning Business" do
        assert_equal @org.business.id, @org2.business.id, "Expected @org and @org2 to belong to the same Business"

        org_job = OrganizationSecurityConfigurationJob.new(
          security_configuration_id: @security_configuration.id,
          organization_id: @org.id,
          actor_id: @user.id,
          action: :apply,
          repository_ids: nil,
          override_existing_config: true,
        )
        org_job_progress_tracker = org_job.job_progress_tracker
        org_job_progress_tracker.start # Normally done when the job is enqueued.

        org2_job = OrganizationSecurityConfigurationJob.new(
          security_configuration_id: @security_configuration.id,
          organization_id: @org2.id,
          actor_id: @user.id,
          action: :apply,
          repository_ids: nil,
          override_existing_config: true,
        )
        org2_job_progress_tracker = org2_job.job_progress_tracker
        org2_job_progress_tracker.start # Normally done when the job is enqueued.

        assert org_job_progress_tracker.class.business_jobs_running?(@org.business.id)
        assert_predicate org_job_progress_tracker, :in_progress?
        assert_predicate org2_job_progress_tracker, :in_progress?

        # Pretend jobs for @org finished:
        assert org_job_progress_tracker.finish
        # Ensure that we still see that @org2 jobs are running for the Business:
        assert org_job_progress_tracker.class.business_jobs_running?(@org.business.id)

        # Finish @org2 jobs:
        assert org2_job_progress_tracker.finish
        # And ensure that we no longer have any jobs running for the Business:
        refute org2_job_progress_tracker.class.business_jobs_running?(@org.business.id)
      end

      test "does not track org ID when not owned by a Business", skip_emu: true do
        job = OrganizationSecurityConfigurationJob.new(
          security_configuration_id: @non_enterprise_security_configuration.id,
          organization_id: @non_enterprise_org.id,
          actor_id: @user.id,
          action: :apply,
          repository_ids: nil,
          override_existing_config: true,
        )
        job_progress_tracker = job.job_progress_tracker
        job_progress_tracker.start # Normally done when the job is enqueued.

        assert_nil @non_enterprise_org.business
        assert_predicate job_progress_tracker, :in_progress?

        # Pretend jobs actually ran and finished:
        assert job_progress_tracker.finish
      end
    end

    context "updating a configuration" do
      test "enqueues jobs to update repositories attached to the configuration" do
        configuration = create(:security_configuration, target: @org)

        create(:repository_security_configuration, state: :attached, repository: @repo1, security_configuration: configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: configuration)

        create(:repository_security_configuration, state: :removed, repository: @repo2, security_configuration: configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update repositories that have the configuration enforced and the enforcement policy changes" do
        # Mimicking a configuration that was enforced, but is then changed to become not enforced
        configuration = create(:security_configuration, target: @org)
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: configuration)
        create(:repository_security_configuration, state: :enforced, repository: @repo3, security_configuration: configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update repositories that have the GH config enforced" do
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :enforced, repository: @repo3, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: @security_configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update only repos in the current org that are attached to the GH config" do
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: @security_configuration)

        other_org = create(:organization)
        other_repo = create(:private_repository, owner: other_org)
        create(:repository_security_configuration, state: :attached, repository: other_repo, security_configuration: @security_configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: {},
            }]
          )
        end
      end

      test "enqueues jobs to update repos attached to config with override params if publish_backfill_group_request is true" do
        security_config = create(:security_configuration, target: @org)
        create(:repository_security_configuration, state: :attached, repository: @repo1, security_configuration: security_config)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: security_config)
        SecurityConfiguration.any_instance.stubs(:any_feature_previously_changed?).returns(true)
        SecurityConfiguration.any_instance.stubs(:secret_scanning_scan_triggering_feature_is_enabled?).returns(true)

        job =
          OrganizationSecurityConfigurationJob.new(
            security_configuration_id: security_config.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update,
            options: { publish_backfill_group_request: true }
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          job.perform_now
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: security_config.id,
              override_params: { skip_backfill_request: "1" },
            }]
          )
        end

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 2, job_progress_tracker.total_jobs
        assert_equal 2, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo1.id, @repo3.id], job_progress_tracker.repository_ids
      end

      test "no-ops for GitHub recommended configuration" do
        assert_no_enqueued_jobs do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end
      end

      test "marks the job progress tracker as finished if no jobs were enqueued" do
        configuration = create(:security_configuration, target: @org)

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            action: :update,
          )
        end

        job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)
        refute_predicate job_progress_tracker, :in_progress?
      end
    end

    context "detaching configurations" do
      test "removes the repository security configuration records for the given repos" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end
        assert_equal 5, RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count

        assert_changes -> { RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count }, from: 5, to: 2 do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: nil,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :detach,
            repository_ids: [@repo1.id, @repo3.id, @archived_repo.id],
          )
        end

        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo1)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo3)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @archived_repo)
      end

      test "removes the repository security configuration records for repos matching a ES search query" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end
        assert_equal 5, RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count

        assert_changes -> { RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count }, from: 5, to: 2 do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: nil,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :detach,
            repository_ids: nil,
            repository_query: "visibility:private",
          )
        end

        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo1)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo2)
      end

      test "removes the repository security configuration records for repos matching a non-ES search query" do
        [@repo1, @repo2, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end
        assert_equal 3, RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count

        assert_changes -> { RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count }, from: 3, to: 0 do
          OrganizationSecurityConfigurationJob.perform_now(
            security_configuration_id: nil,
            organization_id: @org.id,
            actor_id: @user.id,
            action: :detach,
            repository_ids: nil,
            repository_query: "config-status:attached",
          )
        end

        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo1)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo2)
      end
    end

    context "retry conditions" do
      test "retries on dirty exit" do
        assert_retry_on_dirty_exit(
          job: OrganizationSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            override_existing_config: false,
          }]
        )
      end

      test "retries on recoverable exceptions" do
        assert_retry_on_recoverable_exceptions(
          job: OrganizationSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            organization_id: @org.id,
            actor_id: @user.id,
            repository_ids: nil,
            override_existing_config: false,
          }]
        )
      end
    end

    context "preventing license consumption" do
      test "doesn't prevent licenses when the org hasn't purchased GHAS" do
        setup_entity_as_non_ghas(@business)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "doesn't prevent licenses when the org is unlimited" do
        @business.set_advanced_security_seats_for_entity(seats: 0, actor: @user) # Unlimited seats

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "prevents additional bundled licenses when there aren't sufficent licenses" do
        # Stub how many additional committers would be needed:
        stub_turboghas_summary(additional_committers: 2)
        setup_entity_as_bundled_ghas(@business, seats: 1)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new([GitHub::Turboghas::SKU::Bundled]), job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "doesn't prevent licenses when the number of necessary seats is less than remaining seats" do
        # Additional seats is 2, total # of seats is defined in test setup stubs:
        stub_turboghas_summary(additional_committers: 2)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "checks for all repo enablement if repository IDs aren't provided and doesn't block if sufficent seats" do
        stub_turboghas_summary(additional_committers: 2)

        repository_ids = []
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })
        assert_equal Set.new, job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "checks for all repo enablement if repository IDs aren't provided and blocks if insufficent seats" do
        stub_turboghas_summary(additional_committers: 5000)

        repository_ids = []
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })
        assert_equal Set.new([GitHub::Turboghas::SKU::Bundled]), job.prevent_additional_sku_usage(@org, repository_ids)
      end

      test "doesn't prevent licenses if there's an exception" do
        Organization.any_instance.stubs(:advanced_security_purchased?).raises(StandardError) # 💥 Boom! 💥

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new, job.prevent_additional_sku_usage(@org, [])
      end

      test "prevents bundled licenses when the org has already exceeded the max license limit" do
        AdvancedSecurityLicense.any_instance.stubs(:allowance_exceeded?).returns(true)

        repository_ids = [@repo1.id, @repo2.id, @repo3.id, @repo4.id]
        job = SecurityProductsEnablement::OrganizationSecurityConfigurationJob.new({ organization_id: @org.id, repository_ids: })

        assert_equal Set.new([GitHub::Turboghas::SKU::Bundled]), job.prevent_additional_sku_usage(@org, repository_ids)
      end
    end
  end
end
