# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class RepositorySyncJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include JobTestHelper
    include DependabotAlertsEnterpriseEnablementHelper

    fixtures do
      @biz = if GitHub.enterprise?
        create(:global_business)
      else
        create(:business, :enterprise_managed)
      end

      @emu_user = if GitHub.enterprise?
        create(:user, business: @biz)
      else
        create(:emu, business: @biz)
      end

      @owner = create(:user)
      @org = create(:organization, admin: @owner, business: @biz)
      @other_org = create(:organization, admin: @owner, business: @biz)

      @repo = create(:repository, owner: @org)
      @other_repo = create(:repository, owner: @org)

      @repo_in_other_org = create(:repository, owner: @other_org)

      # Enable dependabot alerts since we can't stub them in fixture
      GitHub.enable_ghe_content_analysis(@owner) if GitHub.enterprise?
    end

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      User.any_instance.stubs(:advanced_security_purchased?).returns(true)

      GitHub::Turboscan.stubs(:analyses).returns(Twirp::ClientResp.new(data: Turboscan::Proto::AnalysesResponse.new))
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

      if GitHub.enterprise?
        stub_dependabot_alerts_enterprise_enablement
        GitHub.stubs(code_scanning_enabled?: true)

        # Settings to enable EMU for GHES
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
      end
    end

    context "security_center_update_job_behaviour" do
      test "is only enqueued once per repo, event, and feature" do
        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning", event_timestamp: Time.now.to_f)
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
        end
      end

      test "is only enqueued once per repo and event when feature input is not provided" do
        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof")
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", event_timestamp: Time.now.to_f)
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @repo.id, source_event: "woof")
        end
      end

      test "different repos can have a job running with default inputs for the rest" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @repo.id, source_event: "woof")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @other_repo.id, source_event: "woof")
        end
      end

      test "different repos can have a job running for the same feature_type" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @other_repo.id, source_event: "woof", feature_type: "code_scanning")
        end
      end

      test "different feature_type can have a job running" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "secret_scanning")
        end
      end

      test "different event_source can have a job running" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @repo.id, source_event: "barr", feature_type: "code_scanning")
        end
      end

      test "performs retry when restraint lock is taken" do
        RepositorySyncJob.any_instance.expects(:retry_job)
        Repository.expects(:find_by_id).never
        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          GitHub::Restraint.new.lock!("[repository_id,#{@repo.id}] [feature_type,code_scanning]", 1, 10) do
            RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
          end
        end
      end

      test "records get cleaned up on if repo does not have valid network (malformed)" do
        Organization.any_instance.expects(:advanced_security_purchased?).at_least(1).returns(true)
        repo = create(:repository, owner: @org)

        published_vulnerability = create(:vulnerability)
        vulnerability_alert = create(:repository_vulnerability_alert,
          :open,
          repository: repo,
          vulnerability: published_vulnerability,
          vulnerable_manifest_path: "another/Gemfile.lock",
          affects: "aaa"
        )

        Repository.any_instance.expects(:code_scanning_security_center_status).once.returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled")
        )

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
        end
        refute_equal 0, RepositorySecurityCenterConfig.count
        refute_equal 0, RepositorySecurityCenterStatus.count

        reset_hydro

        Repository.any_instance.stubs(:network).returns(nil)
        RepositorySyncJob.any_instance.expects(:perform_update).never

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
        end

        assert_performed_jobs 2, only: RepositorySyncJob
        assert_equal 0, RepositorySecurityCenterConfig.count
        assert_equal 0, RepositorySecurityCenterStatus.count

        assert_dogstats_increment 1, "security_center.update_job.abort", tags: [
          "cause:repo_without_network"
        ]
      end

      test "dependabot_alerts, code_scanning, and secret_scanning records do not get cleaned up for non-GHAS orgs in GHEC" do
        Organization.any_instance.expects(:advanced_security_purchased?).at_least(1).returns(false)
        Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
        )

        if GitHub.enterprise?
          Repository.any_instance.expects(:code_scanning_security_center_status).never
        else
          Repository.any_instance.expects(:code_scanning_security_center_status).once.returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled")
          )
        end

        repo = create(:repository, owner: @org)

        # Should always be included for public repos
        create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo)
        create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)

        # Should be included for non-enterprise only
        create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo)

        create(:repository_security_center_config, repository: repo)

        assert_equal 3, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
        assert_equal %w[code_scanning dependabot_alerts secret_scanning], RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
        assert_equal @org.id, RepositorySecurityCenterStatus.find_by(repository_id: repo.id).try(:owner_id)
        assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
        end

        if GitHub.enterprise?
          # after running the job, we remove the code_scanning feature (-1) and secret scanning (-2), but we backfill the dependabot (+1) subfeatures
          expected_features = %w[dependabot_alerts dependabot_security_updates]
          assert_equal expected_features.length, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
          assert_equal expected_features.sort, RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
        else
          # after running the job, we backfill the subfeatures for code_scanning (+2) secret_scanning (+1) and dependabot (+1)
          expected_features = %w[code_scanning code_scanning_auto_codeql code_scanning_pr_reviews dependabot_alerts dependabot_security_updates secret_scanning secret_scanning_push_protection]
          actual_features = RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
          assert_equal expected_features.sort, actual_features
        end
        assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count
      end

      test "only secret_scanning records is kept for user owned repos" do
        Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
        )
        Repository.any_instance.stubs(:code_scanning_open_alerts_count).returns(0)

        repo = create(:private_repository, owner: @emu_user)

        # Should always be included for public repos
        create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo)
        create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)

        # Should be included for non-enterprise only
        create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo)

        create(:repository_security_center_config, repository: repo)

        assert_equal 3, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
        assert_equal %w[code_scanning dependabot_alerts secret_scanning], RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
        assert_equal @emu_user.id, RepositorySecurityCenterStatus.find_by(repository_id: repo.id).try(:owner_id)
        assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
        end

        expected_features = %w[secret_scanning secret_scanning_push_protection]
        assert_equal expected_features.length, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
        assert_equal expected_features.sort, RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
        assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count
      end
    end

    context "security_center_retry_behaviour" do
      test "common retries" do
        assert_retry_conditions job: RepositorySyncJob, args: [repository_id: 1, source_event: "woof"]
      end

      test "retries if repo does not exist when read from replica, and attempt to clean up on the last retry" do
        RepositorySyncJob.any_instance.expects(:clear_existing_data).with(0).once
        SecurityCenter::DeadLetterJob.expects(:schedule_for_retry).never

        assert_performed_jobs(RepositorySyncJob::RETRY_EXECUTIONS.size + 1, only: [RepositorySyncJob]) do
          # Repo ID 0 does not exist
          RepositorySyncJob.perform_later(repository_id: 0, source_event: "woof", feature_type: "code_scanning")
        end

        assert_empty Failbot.reports
      end

      test "does not retry if repo isn't found on disk" do
        Repositories::Public.expects(:get_active_or_deleted).raises(GitHub::DGit::NotFoundError).times(1)
        SecurityCenter::DeadLetterJob.expects(:schedule_for_retry).never

        assert_performed_jobs(1, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "repository_configuration")
        end

        assert_empty Failbot.reports
        assert_dogstats_increment 1, "security_center.update_job.abort", tags: [
          "cause:repo_not_in_disk"
        ]
      end

      test "retries on retryable exceptions and schedule DLQ rerun if fails on last retry" do
        Repositories::Public.expects(:get_active_or_deleted).raises(Freno::Throttler::Error.new).times(6)
        SecurityCenter::DeadLetterJob.expects(:schedule_for_retry).once

        Failbot.expects(:report).with(instance_of(Freno::Throttler::Error))

        assert_performed_jobs(RepositorySyncJob::RETRY_EXECUTIONS.size + 1, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning", event_timestamp: 1.to_f)
        end
      end

      test "retries on subclasses of retryable exceptions and schedule DLQ rerun if fails on last retry" do
        Repositories::Public.expects(:get_active_or_deleted).raises(Freno::Throttler::ClientError.new).times(6)
        SecurityCenter::DeadLetterJob.expects(:schedule_for_retry).once

        Failbot.expects(:report).with(instance_of(Freno::Throttler::ClientError))

        now = Time.now.to_f
        assert_performed_jobs(RepositorySyncJob::RETRY_EXECUTIONS.size + 1, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning", event_timestamp: now)
        end
      end

      test "retries with DLQ on none retryable exceptions" do
        Repositories::Public.expects(:get_active_or_deleted).raises(ArgumentError.new("some error"))
        SecurityCenter::DeadLetterJob.expects(:schedule_for_retry).once

        Failbot.expects(:report).with(instance_of(ArgumentError))

        assert_performed_jobs(1, only: [RepositorySyncJob]) do
          assert_raises ArgumentError do
            RepositorySyncJob.perform_later(repository_id: 0, source_event: "woof", feature_type: "code_scanning")
          end
        end
      end

      test "no sync when repo is marked for deletion" do
        repo = create(:repository, owner: @org)
        Repository.any_instance.expects(:security_center_notify).never

        # Don't actually perform the RepositoryOrchestrationJob, so repo is just marked for deletion - not deleted yet
        repo.remove(@owner)

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof", feature_type: "code_scanning")
        end

        assert_performed_jobs 1, only: RepositorySyncJob
      end

      test "no retry when repo is deleted" do
        repo = create(:repository, owner: @org)

        reset_hydro

        repo.remove(@owner, synchronous: true)

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof", feature_type: "code_scanning")
        end

        # Job only attempted once, because repo is properly deleted
        assert_performed_jobs 1, only: RepositorySyncJob
      end

      test "retry_and_eventually_succeed" do
        CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

        # First call to find_by_id returns nil, second return the actual repo
        Repositories::Public.stubs(:get_active_or_deleted).returns(nil).then.returns(@repo)
        Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)

        Repository.any_instance.expects(:code_scanning_security_center_status).once.returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled")
        )

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
        end

        # The job ran once and failed, got retried and succeeded
        assert_performed_jobs 2
        # Assert that the status got updated
        status = @repo.security_center_status_for_feature("code_scanning")
        refute_nil status
        assert_equal "not_enrolled", status.scanning_status
        assert_equal @org.id, status.owner_id
      end

      test "retry when code scanning default setup is still enabling" do
        # Stubs away data function so test can focus on verifying retry flow
        Repository.any_instance.stubs(:security_center_notify)
        CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(true)
        Repository.any_instance.stubs(:code_scanning_open_alerts_count).returns(0)

        repo = create(:repository, owner: @org)

        assert_performed_jobs(6, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "repo.code_scanning_status_refreshed", feature_type: "code_scanning")
        end
      end

      test "retry when code scanning throws AutoCodeqlError" do
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).raises(CodeScanning::AutoCodeqlError.new("boom"))

        repo = create(:repository, owner: @org)

        assert_performed_jobs(RepositorySyncJob::RETRY_EXECUTIONS.size + 1, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "repo.code_scanning_status_refreshed", feature_type: "code_scanning")
        end
      end
    end

    context "reconciliation fanout" do
      test "includes trigger in telemetry" do
        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", feature_type: "dependabot_alerts")
        end

        assert_dogstats_distribution("security_center.update_job.dist", tags: ["feature_type_input:dependabot_alerts", "source_event:woof"])
      end
    end

    context "security_center.repository_updated" do
      test "is recorded when event_timestamp is available" do
        # Stubs away data function so test can focus on verifying retry flow
        Repository.any_instance.stubs(:security_center_notify)

        event_timestamp = 1.second.ago.to_f
        frozen_now = Time.now
        Timecop.freeze frozen_now do
          perform_enqueued_jobs(only: [RepositorySyncJob]) do
            RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof", event_timestamp: event_timestamp)
          end
          assert_dogstats_distribution_value(
            (frozen_now.to_f - event_timestamp) * 1_000,
            "security_center.repository_updated.dist"
          )
        end
      end

      test "is not recorded when event_timestamp is absent" do
        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @repo.id, source_event: "woof")
        end
        assert_dogstats_distribution(0, "security_center.repository_updated.dist")
      end
    end

    context "perform update" do
      test "notifies when all features are included" do
        Repository.any_instance.expects(:security_center_notify).times(4)

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_now(repository_id: @repo.id, source_event: "woof")
        end
      end

      test "notifies when feature type is in visible features" do
        Repository.any_instance.expects(:security_center_notify).once

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_now(repository_id: @repo.id, source_event: "woof", feature_type: "code_scanning")
        end
      end

      test "does not notify when feature type is not in visible features" do
        Repository.any_instance.expects(:security_center_notify).never

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_now(repository_id: @repo.id, source_event: "woof", feature_type: "unknown")
        end
      end
    end
  end

  class RepositorySyncJobEnterpriseManagedUsersTest < GitHub::TestCase
    skip_enterprise

    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include JobTestHelper
    include DependabotAlertsEnterpriseEnablementHelper

    fixtures do
      @business = create(:business, :enterprise_managed)
      @admin = @business.find_first_emu_owner
      @emu = create(:emu, business: @business)
      @emu_repo = create(:private_repository, force_user_owned: true, owner: @emu)
      @emu_repo2 = create(:private_repository, force_user_owned: true, owner: @emu)
    end

    setup do
      setup_advanced_security(@business, @admin, true)
      GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      if GitHub.enterprise?
        stub_dependabot_alerts_enterprise_enablement
      end
    end

    def setup_advanced_security(business, user, enablement_status)
      if GitHub.enterprise?
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(enablement_status)
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(enablement_status)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10) if enablement_status
      else
        if enablement_status
          business.mark_advanced_security_as_purchased_for_entity(actor: user)
          business.set_advanced_security_seats_for_entity(actor: user, seats: 10)
        else
          business.mark_advanced_security_as_not_purchased_for_entity(actor: user)
        end
      end
    end

    test "dependabot_alerts, code_scanning, and secret_scanning records get cleaned up for non-GHAS users" do
      setup_advanced_security(@business, @admin, false)
      GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

      Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
      )

      repo = create(:private_repository, force_user_owned: true, owner: @emu)

      create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo)
      create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)

      # Should be included for non-enterprise only
      create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo)

      create(:repository_security_center_config, repository: repo)

      assert_equal %w[code_scanning dependabot_alerts secret_scanning], RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
      assert_equal @emu.id, RepositorySecurityCenterStatus.find_by(repository_id: repo.id).try(:owner_id)
      assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count

      perform_enqueued_jobs(only: [RepositorySyncJob]) do
        RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
      end

      # after running the job, we remove all statuses and config entries
      assert_equal 0, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
      assert_equal 0, RepositorySecurityCenterConfig.where(repository_id: repo.id).count
    end

    test "cleans up everything for non-EMU accounts", skip_enterprise: true do
      rando = create(:user)
      repo = create(:private_repository, owner: rando)

      Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
      )

      # for some reason, all these records exist
      create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo)
      create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
      create(:repository_security_center_config, repository: repo)

      assert_equal %w[dependabot_alerts secret_scanning], RepositorySecurityCenterStatus.where(repository_id: repo.id).map { |s| s.feature_type }.sort
      assert_equal rando.id, RepositorySecurityCenterStatus.find_by(repository_id: repo.id).try(:owner_id)
      assert_equal 1, RepositorySecurityCenterConfig.where(repository_id: repo.id).count

      perform_enqueued_jobs(only: [RepositorySyncJob]) do
        RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "woof")
      end

      # after running the job, we remove all statuses and config entries
      assert_equal 0, RepositorySecurityCenterStatus.where(repository_id: repo.id).count
      assert_equal 0, RepositorySecurityCenterConfig.where(repository_id: repo.id).count
    end

    context "security_center_update_job_behaviour" do
      test "is only enqueued once per repo, event, and feature" do
        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning", event_timestamp: Time.now.to_f)
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
        end
      end

      test "is only enqueued once per repo and event when feature input is not provided" do
        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof")
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", event_timestamp: Time.now.to_f)
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo.id, source_event: "woof")
        end
      end

      test "different repos can have a job running with default inputs for the rest" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @emu_repo.id, source_event: "woof")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo2.id, source_event: "woof")
        end
      end

      test "different repos can have a job running for the same feature_type" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo2.id, source_event: "woof", feature_type: "code_scanning")
        end
      end

      test "different feature_type can have a job running" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "secret_scanning")
        end
      end

      test "different event_source can have a job running" do
        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          RepositorySyncJob.set(wait: 1.second).perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
          RepositorySyncJob.set(wait: 1.minute).perform_later(repository_id: @emu_repo.id, source_event: "barr", feature_type: "code_scanning")
        end
      end

      test "performs retry when restraint lock is taken" do
        RepositorySyncJob.any_instance.expects(:retry_job)
        Repository.expects(:find_by_id).never
        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          GitHub::Restraint.new.lock!("[repository_id,#{@emu_repo.id}] [feature_type,code_scanning]", 1, 10) do
            RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "code_scanning")
          end
        end
      end
    end

    context "security_center_retry_behaviour" do
      test "common retries" do
        assert_retry_conditions job: RepositorySyncJob, args: [repository_id: 1, source_event: "woof"]
      end

      # This is a mirror to the test elsewhere in this file that ensures the sync job is retried
      # for org repos where code-scanning is reported to still be enabling.
      # The setup is the same, but in this test we only expect the job for EMU repos to run once
      test "ignores code-scanning when it still enabling" do
        # Stubs away data function so test can focus on verifying retry flow
        Repository.any_instance.stubs(:security_center_notify)
        CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(true)

        repo = create(:private_repository, force_user_owned: true, owner: @emu)

        assert_performed_jobs(1, only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: repo.id, source_event: "repo.code_scanning_status_refreshed", feature_type: "code_scanning")
        end
      end
    end

    context "reconciliation fanout" do
      test "includes trigger in telemetry" do
        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", feature_type: "dependabot_alerts")
        end

        assert_dogstats_distribution("security_center.update_job.dist", tags: ["feature_type_input:dependabot_alerts", "source_event:woof"])
      end
    end

    context "security_center.repository_updated" do
      test "is recorded when event_timestamp is available" do
        # Stubs away data function so test can focus on verifying telemetry
        Repository.any_instance.stubs(:security_center_notify)

        event_timestamp = 1.second.ago.to_f
        frozen_now = Time.now
        Timecop.freeze frozen_now do
          perform_enqueued_jobs(only: [RepositorySyncJob]) do
            RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof", event_timestamp: event_timestamp)
          end
          assert_dogstats_distribution_value(
            (frozen_now.to_f - event_timestamp) * 1_000,
            "security_center.repository_updated.dist"
          )
        end
      end

      test "is not recorded when event_timestamp is absent" do
        # Stubs away data function so test can focus on verifying telemetry
        Repository.any_instance.stubs(:security_center_notify)

        perform_enqueued_jobs(only: [RepositorySyncJob]) do
          RepositorySyncJob.perform_later(repository_id: @emu_repo.id, source_event: "woof")
        end
        assert_dogstats_distribution(0, "security_center.repository_updated.dist")
      end
    end
  end
end
