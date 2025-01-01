# rubocop:disable GitHub/DoNotUseGlobalKv
# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityAnalysisSettingsUpdateJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include JobTestHelper

  setup do
    SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs)
      .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

    GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?

    SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:enabled?).returns(true)
  end

  test "retry conditions" do
    owner = create(:organization)
    assert_retry_conditions(job: SecurityAnalysisSettingsUpdateJob, args: [{
      actor: owner,
      owner: owner,
      update_type: :job_test_action
    }])
  end

  context ".job_id_business_prefix" do
    test "returns the correct job id prefix" do
      business = create(:global_business)
      expected = "security_analysis_settings_update_job.#{business.id}"
      actual = SecurityAnalysisSettingsUpdateJob.job_id_business_prefix(business)
      assert_equal(expected, actual)
    end

    context "when business is nil" do
      test "returns the correct job id prefix" do
        expected = "security_analysis_settings_update_job.0"
        actual = SecurityAnalysisSettingsUpdateJob.job_id_business_prefix(nil)
        assert_equal(expected, actual)
      end
    end
  end

  context ".job_id_owner_prefix" do
    context "when owner is an Organization" do
      test "returns the correct job id prefix" do
        business = create(:global_business)
        organization = create(:business_plus_organization, business: business)
        expected = "security_analysis_settings_update_job.#{business.id}.#{organization.id}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(organization)
        assert_equal(expected, actual)
      end

      context "when business is nil" do
        test "returns the correct job id prefix" do
          organization = create(:organization)
          expected = "security_analysis_settings_update_job.0.#{organization.id}"
          actual = SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(organization)
          assert_equal(expected, actual)
        end
      end
    end

    context "when owner is a User" do
      test "returns the correct job id prefix" do
        user = create(:user)
        expected = "security_analysis_settings_update_job.0.#{user.id}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(user)
        assert_equal(expected, actual)
      end

      test "returns the correct job id prefix when user is an enterprise managed user", skip_enterprise: true do
        emu_admin = create(:user)
        emu_biz = create(:business, :enterprise_managed)
        emu_biz.mark_advanced_security_as_purchased_for_entity(actor: emu_admin)
        emu_user = create(:emu, business: emu_biz)

        expected = "security_analysis_settings_update_job.#{emu_biz.id}.#{emu_user.id}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(emu_user)
        assert_equal(expected, actual)
      end

      test "does not include business id when feature is off", enterprise_only: true do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)

        admin = create(:user)
        biz = create(:global_business)
        biz.mark_advanced_security_as_purchased_for_entity(actor: admin)
        user = create(:user)

        expected = "security_analysis_settings_update_job.0.#{user.id}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(user)
        assert_equal(expected, actual)
      end
    end
  end

  context ".job_id" do
    context "when owner is an Organization" do
      test "returns the correct job id" do
        business = create(:global_business)
        organization = create(:business_plus_organization, business: business)
        update_type = :secret_scanning_enable_all
        expected = "security_analysis_settings_update_job.#{business.id}.#{organization.id}.#{update_type}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id(organization, update_type)
        assert_equal(expected, actual)
      end

      context "when business is nil" do
        test "returns the correct job id " do
          organization = create(:organization)
          update_type = :secret_scanning_enable_all
          expected = "security_analysis_settings_update_job.0.#{organization.id}.#{update_type}"
          actual = SecurityAnalysisSettingsUpdateJob.job_id(organization, update_type)
          assert_equal(expected, actual)
        end
      end
    end

    context "when owner is a User" do
      test "returns the correct job id" do
        user = create(:user)
        update_type = :secret_scanning_enable_all
        expected = "security_analysis_settings_update_job.0.#{user.id}.#{update_type}"
        actual = SecurityAnalysisSettingsUpdateJob.job_id(user, update_type)
        assert_equal(expected, actual)
      end
    end
  end

  context ".status" do
    test "returns the correct job status" do
      owner = create(:organization)
      update_type = :secret_scanning_enable_all
      job_status = SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(owner, update_type) })
      assert_equal(SecurityAnalysisSettingsUpdateJob.status(owner, update_type).try(:id), job_status.id)
    end
  end

  context "#perform" do
    test "expected logs are generated" do
      owner = create(:organization)
      repos = create_list(:repository, 3, :private, owner: owner)

      expected_logs = {
        "enduser.id": owner.display_login,
        "gh.enduser.id": owner.id,
        "gh.enduser.login": owner.display_login,
        "gh.security_products.job.emit_backfill_group_request": true,
        "gh.security_products.job.initial_start": /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{6})Z/,
        "gh.job.name": "SecurityAnalysisSettingsUpdateJob",
        "gh.security_products.job.offset_id": /\d+/,
        "gh.security_products.job.num_applicable_repos": repos.size,
        "gh.org.id": owner.id,
        "gh.org.login": owner.display_login,
        "gh.owner.id": owner.id,
        "gh.owner.login": owner.display_login,
        "gh.security_products.job.sequence_duration_sec": /\d+(\.\d+)?/,
        "gh.security_products.job.sequence_id": /[a-zA-Z0-9-]+/,
        "gh.security_products.job.update_type": :job_test_action
      }

      assert_logged(**expected_logs) do
        perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :job_test_action
          )
        end
      end
    end

    test "logs repo-level exceptions without raising" do
      owner = create(:organization)

      error_repo = create(:repository, owner: owner)
      service_manager_instance = stub("SecurityProduct::ServiceManager")
      service_manager_instance.expects(:toggle_services_with_form_inputs)
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, ArgumentError.new("test error")))
      SecurityProduct::ServiceManager.expects(:new).with(error_repo).returns(service_manager_instance)

      create_list(:repository, 3, :private, owner: owner).each do |repo|
        service_manager_instance = stub("SecurityProduct::ServiceManager")
        service_manager_instance.expects(:toggle_services_with_form_inputs)
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
        SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
      end

      expected_logs = {
        "gh.repo.id" => error_repo.id,
        "gh.repo.name" => error_repo.name,
        "exception.type" => "ArgumentError",
        "exception.message" => "test error",
        "exception.stacktrace" => /.*/
      }

      assert_logged(**expected_logs) do
        perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :job_test_action
          )
        end
      end
    end

    context "SecurityProductsEnablement::JobStatus" do
      test "creates aSecurityProductsEnablement::JobStatus when performed synchronously" do
        owner = create(:organization)

        assert_changes(
          -> { SecurityAnalysisSettingsUpdateJob.status(owner, :job_test_action) },
          from: nil
        ) do
          SecurityAnalysisSettingsUpdateJob.perform_now(
            actor: owner,
            owner: owner,
            update_type: :job_test_action
          )
        end
      end

      test "creates aSecurityProductsEnablement::JobStatus when performed asynchronously" do
        owner = create(:organization)

        assert_changes(
          -> { SecurityAnalysisSettingsUpdateJob.status(owner, :job_test_action) },
          from: nil
        ) do
          perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
            SecurityAnalysisSettingsUpdateJob.perform_later(
              actor: owner,
              owner: owner,
              update_type: :job_test_action
            )
          end
        end
      end

      test "sets the SecurityProductsEnablement::JobStatus to success" do
        owner = create(:organization)

        assert_changes(
          -> { SecurityAnalysisSettingsUpdateJob.status(owner, :job_test_action).try(:success?) },
          from: nil,
          to: true
        ) do
          SecurityAnalysisSettingsUpdateJob.perform_now(
            actor: owner,
            owner: owner,
            update_type: :job_test_action
          )
        end
      end

      test "sets the SecurityProductsEnablement::JobStatus to error if an exception is raised" do
        owner = create(:organization)
        create(:private_repository, owner: owner)

        assert_changes(
          -> { SecurityAnalysisSettingsUpdateJob.status(owner, :job_test_action).try(:error?) },
          from: nil,
          to: true
        ) do
          assert_raises do
            SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs).raises(StandardError.new("BOOM!"))
            SecurityAnalysisSettingsUpdateJob.perform_now(
              actor: owner,
              owner: owner,
              update_type: :job_test_action
            )
          end
        end
      end
    end

    test "enqueues subsequent jobs when there are more repos to process" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)

      SecurityAnalysisSettingsUpdateJob
        .any_instance
        .stubs(:timeout_sec)
        .returns(0.0)

      assert_performed_jobs(4, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action
        )
      end
    end

    test "emits telemetry on long running sequences once" do
      owner = create(:organization)
      create_list(:repository, 3, owner: owner)

      SecurityAnalysisSettingsUpdateJob
        .any_instance
        .stubs(:timeout_sec)
        .returns(0.0)

      assert_performed_jobs(4, only: [SecurityAnalysisSettingsUpdateJob]) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          initial_start: Time.current - SecurityAnalysisSettingsUpdateJob::LONG_RUNNING_SEQUENCE_HOURS.hours - 1.minute,
          owner: owner,
          update_type: :job_test_action
        )
      end

      assert_dogstats_increment(1, "security_analysis_settings_update_job.emit_telemetry_on_long_running_sequence")
    end

    test "emits enablement metric on success/failure" do
      SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs)
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
        .then
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
        .then
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, "error"))

      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action
        )
      end

      assert_dogstats_increment 2, "ghas.business.enablement_result", tags: ["update_type:job_test_action", "success:true"]
      assert_dogstats_increment 1, "ghas.business.enablement_result", tags: ["update_type:job_test_action", "success:false"]
    end

    test "emits enablement time on completion of an organization" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action
        )
      end

      assert_dogstats_distribution(1, "ghas.org.enablement_time")
    end

    test "emits enablement time on completion of a business" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .returns(0)
        .times(1)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action,
          business_enable: true,
          business_enablement_started_at: initially_enqueued_at,
          parent_initial_sequence_id: initial_sequence_id
        )
      end

      assert_dogstats_distribution(1, "ghas.business.enablement_time")
    end

    test "does not emit a metric for business enablement when the counter does not go to 0" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .returns(1)
        .times(1)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action,
          business_enable: true,
          business_enablement_started_at: initially_enqueued_at,
          parent_initial_sequence_id: initial_sequence_id
        )
      end

      assert_dogstats_distribution(0, "ghas.business.enablement_time")
    end

    test "does not emit a metric for business enablement when decrementing the counter fails" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .raises(StandardError)
        .times(1)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action,
          business_enable: true,
          business_enablement_started_at: initially_enqueued_at,
          parent_initial_sequence_id: initial_sequence_id
        )
      end

      assert_dogstats_distribution(0, "ghas.business.enablement_time")
    end

    test "decrements the counter on if the job cannot be enqueued because of args" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .returns(1)
        .times(1)

      assert_performed_jobs(0, only: SecurityAnalysisSettingsUpdateJob) do
        begin
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            update_type: :job_test_action,
            business_enable: true,
            business_enablement_started_at: initially_enqueued_at,
            parent_initial_sequence_id: initial_sequence_id
          )
        rescue # rubocop:disable Lint/GenericRescue
        end
      end

      assert_dogstats_distribution(0, "ghas.business.enablement_time")
    end

    test "does not decrement the counter if there is no business enablement started at value" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .returns(1)
        .times(0)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action,
          business_enable: true,
          parent_initial_sequence_id: initial_sequence_id
        )
      end

      assert_dogstats_distribution(0, "ghas.business.enablement_time")
    end

    test "does not decrement the counter if there is no business enablement sequence id" do
      owner = create(:organization)
      create_list(:repository, 3, :private, owner: owner)
      initially_enqueued_at = Time.now
      initial_sequence_id = "abc"
      SecurityProductsEnablement::KV.store
        .stubs(:increment)
        .with do |args|
          assert_equal "business_enablement:counter:#{initial_sequence_id}", args
        end
        .returns(1)
        .times(0)

      assert_performed_jobs(1, only: SecurityAnalysisSettingsUpdateJob) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :job_test_action,
          business_enable: true,
          business_enablement_started_at: initially_enqueued_at,
        )
      end

      assert_dogstats_distribution(0, "ghas.business.enablement_time")
    end

    context "non-Dependency Graph and non-GHAS update types" do
      test "security settings for all repositories in the organization are updated" do
        owner = create(:organization)
        repos = create_list(:repository, 3, owner: owner)

        repos.each do |repo|
          service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
          service_manager_instance.expects(:toggle_services_with_form_inputs).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
          SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
        end

        perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :job_test_action
          )
        end
      end
    end

    context "Dependency Graph and GHAS update types" do
      test "updates security settings for only private repositories", skip_enterprise: true do
        owner = create(:organization)
        public_repos = create_list(:repository, 3, :public, owner: owner)
        private_repos = create_list(:repository, 3, :private, owner: owner)

        public_repos.each do |repo|
          SecurityProduct::ServiceManager.expects(:new).with(repo).never
        end

        [:advanced_security_enable_all, :advanced_security_disable_all, :dependency_graph_enable_all, :dependency_graph_disable_all].each do |update_type|
          private_repos.each do |repo|
            service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
            service_manager_instance.expects(:toggle_services_with_form_inputs)
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
            SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
          end

          perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
            SecurityAnalysisSettingsUpdateJob.perform_later(
              actor: owner,
              owner: owner,
              update_type: update_type
            )
          end
        end
      end

      test "updates security settings for all repositories", enterprise_only: true do
        owner = create(:organization)
        public_repos = create_list(:repository, 3, :public, owner: owner)
        private_repos = create_list(:repository, 3, :private, owner: owner)

        [:advanced_security_enable_all, :advanced_security_disable_all, :dependency_graph_enable_all, :dependency_graph_disable_all].each do |update_type|
          (public_repos + private_repos).each do |repo|
            service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
            service_manager_instance.expects(:toggle_services_with_form_inputs)
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
            SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
          end

          perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
            SecurityAnalysisSettingsUpdateJob.perform_later(
              actor: owner,
              owner: owner,
              update_type: update_type
            )
          end
        end
      end
    end

    context "Code Scanning update types" do
      test "invokes auto codeql enablement for all repositories" do
        owner = create(:organization)
        repos = create_list(:repository, 3, owner: owner)

        repos.each do |repo|
          service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
          service_manager_instance.expects(:toggle_services_with_form_inputs)
            .with do |actor, kwargs|
              actor == owner &&
                kwargs.dig(:params, :auto_codeql_enabled) == "1" &&
                kwargs.dig(:params, :bulk) == "1" &&
                kwargs.dig(:params, :fail_on_manual_workflow) == "1" &&
                kwargs.dig(:params, :skip_if_enabled) == "1"
            end
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
          SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
        end

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "invokes auto codeql extended query suite enablement for all repositories" do
        owner = create(:organization)
        repos = create_list(:repository, 3, owner: owner)

        repos.each do |repo|
          service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
          service_manager_instance.expects(:toggle_services_with_form_inputs)
            .with do |actor, kwargs|
              actor == owner &&
                kwargs.dig(:params, :auto_codeql_enabled) == "1" &&
                kwargs.dig(:params, :bulk) == "1" &&
                kwargs.dig(:params, :fail_on_manual_workflow) == "1" &&
                kwargs.dig(:params, :auto_codeql_query_suite) == "extended" &&
                kwargs.dig(:params, :skip_if_enabled) == "1"
            end
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
          SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
        end

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all_extended
          )
        end
      end

      test "invokes auto codeql disablement for all repositories" do
        owner = create(:organization)
        repos = create_list(:repository, 3, owner: owner)

        repos.each do |repo|
          service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
          service_manager_instance.expects(:toggle_services_with_form_inputs)
            .with { |actor, kwargs| actor == owner && kwargs.dig(:params, :auto_codeql_enabled) == "0" }
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
          SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
        end

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_disable_all
          )
        end
      end

      test "retries batch on circuit breaker error" do
        owner = create(:organization)
        repo = create(:repository, owner: owner)

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        # avoid checking turboscan to know if auto_codeql is enabled
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

        # eligibility check always succeeds
        CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).twice
          .returns(SecurityProduct::Result.new(true))

        # errors first time, succeeds second time
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).twice
          .returns(SecurityProduct::Result.new(
            SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {}),
            CodeScanning::AutoCodeqlError.new("boom", repo_id: repo.id, twirp_error: nil)
          ))
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {})))

        assert_performed_jobs(2, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "does not retry on turboscan error" do
        owner = create(:organization)
        repo = create(:repository, owner: owner)

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        # avoid checking turboscan to know if auto_codeql is enabled
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

        # eligibility check succeeds
        CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once
          .returns(SecurityProduct::Result.new(true))

        # enablement fails
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(
            SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {}),
            CodeScanning::AutoCodeqlError.new("boom", repo_id: repo.id, twirp_error: :foo)
          ))

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "does not retry on failed eligibility condition" do
        owner = create(:organization)
        repos = create_list(:repository, 1, owner: owner)

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        # avoid checking turboscan to know if auto_codeql is enabled
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

        # eligibility check fails
        CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once
          .returns(SecurityProduct::Result.new(false, :some_eligibility_condition))

        # enablement never attempted
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).never

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "enable auto_codeql in a repo that contains recommended languages", skip_enterprise: true do
        owner = create(:organization)
        repos = create_list(:repository, 1, owner: owner)

        repo = repos.first
        js = create(:language, language_name: create(:language_name, name: "Javascript"))
        repo.update(languages: [js])

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        # avoid checking turboscan to know if auto_codeql is enabled
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

        # enablement attempted
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {})))

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "enable auto_codeql in a repo that contains CodeQL language", skip_enterprise: true do
        owner = create(:organization)
        repos = create_list(:repository, 1, owner: owner)

        repo = repos.first
        java = create(:language, language_name: create(:language_name, name: "Java"))
        repo.update(languages: [java])

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        # avoid checking turboscan to know if auto_codeql is enabled
        CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

        # enablement attempted
        CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
          .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {})))

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end

      test "does not try to enable auto_codeql in a repo that already has it enabled" do
        owner = create(:organization)
        repos = create_list(:repository, 2, owner: owner)

        js_name = create(:language_name, name: "Javascript")
        repos.each { |repo| repo.update(languages: [create(:language, language_name: js_name)]) }

        SecurityProduct::ServiceManager.any_instance.unstub(:toggle_services_with_form_inputs)

        first_aql = CodeScanning::AutoCodeql.new(repos.first)
        first_aql.expects(:enabled_with_options?).once.returns(true)
        first_aql.expects(:on_enable).never

        # Validate the reverse to make sure only the response of `enabled?` is affecting the resulting expectations
        last_aql = CodeScanning::AutoCodeql.new(repos.last)
        last_aql.expects(:enabled_with_options?).once.returns(false)
        last_aql.expects(:on_enable).once.returns(
          SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {}))
        )

        CodeScanning::AutoCodeql.stubs(:new).with(repos.first, anything).returns(first_aql)
        CodeScanning::AutoCodeql.stubs(:new).with(repos.last, anything).returns(last_aql)
        CodeScanning::AutoCodeql.any_instance.stubs(:can_enable?).returns(SecurityProduct::Result.new(true))

        assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: owner,
            owner: owner,
            update_type: :auto_codeql_enable_all
          )
        end
      end
    end

    context "Secret Scanning update types" do
      context "update_type is :secret_scanning_enable_all or :secret_scanning_disable_all or :secret_scanning_generic_secrets_enable_all or :secret_scanning_generic_secrets_disable_all or :secret_scanning_lower_confidence_patterns_enable_all or :secret_scanning_lower_confidence_patterns_disable_all" do
        test "publishes a BackfillGroupRequest message at the end of the sequence" do
          owner = create(:organization)
          create_list(:repository, 3, owner: owner)

          SecurityAnalysisSettingsUpdateJob
            .any_instance
            .stubs(:timeout_sec)
            .returns(0.0)

          [:secret_scanning_enable_all, :secret_scanning_disable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].each do |update_type|
            reset_hydro
            assert_performed_jobs(4, only: [SecurityAnalysisSettingsUpdateJob]) do
              SecurityAnalysisSettingsUpdateJob.perform_later(
                actor: owner,
                owner: owner,
                update_type: update_type
              )
            end
            assert_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest", count: 1)
            should_start_backfill = [:secret_scanning_enable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_lower_confidence_patterns_enable_all].include?(update_type)
            group_type = :FULL
            if [:secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all].include?(update_type)
              group_type = :GENERIC_SECRETS
            elsif [:secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].include?(update_type)
              group_type = :LOW_CONFIDENCE_PATTERN
            end
            assert_hydro_published_partial({
              owner_id: owner.id,
              owner_scope: :ORGANIZATION_SCOPE,
              action: should_start_backfill ? :START : :CANCEL,
              backfill_type: group_type,
              feature_flags: [
                SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
                SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
                SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
              ],
              security_configuration_id: nil,
            }, schema: "token_scanning_service.v0.BackfillGroupRequest")
            refute_hydro_messages(schema: "token_scanning_service.v0.BackfillRequest")
          end
        end

        test "does not publish a BackfillGroupRequest message if there were no repositories" do
          # empty organization
          owner = create(:organization)
          assert owner.repositories.count == 0

          [:secret_scanning_enable_all, :secret_scanning_disable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].each do |update_type|
            perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
              SecurityAnalysisSettingsUpdateJob.perform_later(
                actor: owner,
                emit_backfill_group_request: true,
                owner: owner,
                update_type: update_type
              )
            end
          end

          refute_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest")
        end

        context "emit_backfill_group_request is false" do
          test "does not publish a BackfillGroupRequest message" do
            owner = create(:organization)
            create_list(:repository, 3, :private, owner: owner)

            [:secret_scanning_enable_all, :secret_scanning_disable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].each do |update_type|
              perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
                SecurityAnalysisSettingsUpdateJob.perform_later(
                  actor: owner,
                  emit_backfill_group_request: false,
                  owner: owner,
                  update_type: update_type
                )
              end
            end

            refute_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest")
          end
        end
      end

      context "update_type is not :secret_scanning_enable_all or :secret_scanning_disable_all or :secret_scanning_generic_secrets_enable_all or :secret_scanning_generic_secrets_disable_all or :secret_scanning_lower_confidence_patterns_enable_all or :secret_scanning_lower_confidence_patterns_disable_all" do
        test "does not publish a BackfillGroupRequest message" do
          owner = create(:organization)
          create_list(:repository, 3, :private, owner: owner)

          perform_enqueued_jobs(only: [SecurityAnalysisSettingsUpdateJob]) do
            SecurityAnalysisSettingsUpdateJob.perform_later(
              actor: owner,
              owner: owner,
              update_type: :auto_codeql_enable_all
            )
          end

          refute_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest")
        end
      end
    end
  end

  context "when an organization has securtiy_configurations enabled" do
    test "enables grouped security updates when repository has security updates enabled" do
      owner = create(:organization)
      repos = create_list(:repository, 3, owner: owner)
      Repository.any_instance.stubs(:vulnerability_updates_enabled?).returns(true)

      repos.each do |repo|
        service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
        service_manager_instance.expects(:toggle_services_with_form_inputs)
        .with do |actor, kwargs|
          actor == owner &&
          kwargs.dig(:params, :vulnerability_updates_grouping_enabled) == "1"
        end
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
        SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
      end
      assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :vulnerability_updates_grouping_enable_all
        )
      end
    end

    test "disables grouped security updates when repository has security updates disabled" do
      owner = create(:organization)
      repos = create_list(:repository, 3, owner: owner)

      repos.each do |repo|
        service_manager_instance = stub("SecurityProduct::ServiceManager", toggle_services_with_form_inputs: nil)
        service_manager_instance.expects(:toggle_services_with_form_inputs)
        .with do |actor, kwargs|
          actor == owner &&
          kwargs.dig(:params, :vulnerability_updates_grouping_enabled) == "0"
        end
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
        SecurityProduct::ServiceManager.expects(:new).with(repo).returns(service_manager_instance)
      end
      assert_performed_jobs(1, only: [SecurityAnalysisSettingsUpdateJob]) do
        SecurityAnalysisSettingsUpdateJob.perform_later(
          actor: owner,
          owner: owner,
          update_type: :vulnerability_updates_grouping_enable_all
        )
      end
    end
  end
end
