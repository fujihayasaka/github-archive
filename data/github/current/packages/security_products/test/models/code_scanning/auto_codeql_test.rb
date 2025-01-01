# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../helpers/advanced_security_skus_base_test"

# Some of the tests here run in both bundled- and split-SKU modes.
# those are defined using `skus_test` as opposed to just `test`;
# see the base class for more about that.
#
# Tests which stub `can_enable?` just run in bundled mode since the
# `can_enable?`` method is where most of the SKU differences are.
# These tests are defined with the regular `test` method, therefore.
class AutoCodeqlTest < AdvancedSecuritySKUsBaseTest
  # Don't put anything in fixtures which has different behaviour in
  # bundled- and split-SKU modes, since fixtures only run once at the
  # beginning of the test run
  fixtures do
    @user = create :user
    @org = create :organization, admin: @user
    @public_repo = create(:public_repository, id: 1, owner: @user)
    @private_repo = create(:private_repository, id: 2, owner: @org)
    @public_org_repo = create(:public_repository, id: 3, owner: @org)

    @ruby = create(:language, language_name: create(:language_name, name: "Ruby"))
    @java = create(:language, language_name: create(:language_name, name: "Java"))
    @kotlin = create(:language, language_name: create(:language_name, name: "Kotlin"))
    @bash = create(:language, language_name: create(:language_name, name: "Bash"))
    @python = create(:language, language_name: create(:language_name, name: "Python"))
    @js = create(:language, language_name: create(:language_name, name: "Javascript"))
    @cpp = create(:language, language_name: create(:language_name, name: "C++"))
  end

  setup do
    do_purchase(entity: @org, actor: @user)

    enable_service(@private_repo, actor: @user)
    enable_service(@public_org_repo, actor: @user) if GitHub.enterprise?

    GitHub.stubs(:code_scanning_enabled?).returns(true)
    GitHub.stubs(:actions_enabled?).returns(true)

    SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(false)

    # The Turboscan connection is memoized, so we need to use a single dogstats instance
    @dogstats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(@dogstats)
  end

  context "enable/disable/update Auto CodeQL" do
    test "there is no error if Auto CodeQL was successfully enabled for (public org-owned) repo" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))
      CodeScanning::AutoCodeql.any_instance.expects(:dismiss_yml).returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        Turbocassette.use(cassette) do
          assert_nil SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
        end
      end
    end

    test "there is no error if Auto CodeQL was successfully enabled for (private) repo" do
      @private_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @private_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))
      CodeScanning::AutoCodeql.any_instance.expects(:dismiss_yml).returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
      Turbocassette.use(cassette) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
      end
    end

    skus_test "there is no error if Auto CodeQL was successfully updated for (public dotcom) repo", skip_enterprise: true do
      @public_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
        assert_nil SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]]).error
      end
    end

    test "there is no error if Auto CodeQL was successfully updated for (public org-owned) repo" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
          assert_nil SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]]).error
        end
      end
    end

    test "there is no error if Auto CodeQL was successfully updated for (private) repo" do
      @private_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @private_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]]).error
      end
    end

    test "there is no error when a noop update is submitted" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-update-noop", persist_with: :turboscan) do
          assert_nil SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]]).error
        end
      end
    end

    test "we know to enable the repo when the repo is not already enabled and no option is supplied" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      cassettes = [
        { name: "code-scanning/counts-absent" },
        { name: "code-scanning/get-managed-analysis-info-disabled" },
        { name: "code-scanning/get-tool-status-messages-outdated" },
      ].map { |c| c.merge(options: { persist_with: :turboscan }) }

      enable_cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
      VCR.use_cassettes(cassettes) do
        VCR.use_cassette(enable_cassette, persist_with: :turboscan, allow_unused_http_interactions: false) do
          result = SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { languages: ["ruby"] }]])
          assert_nil result.error
        end
      end
    end

    test "we know to update the config when the repo is already enabled and no option is supplied" do
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))

      cassettes = [
        { name: "code-scanning/counts-absent" },
        { name: "code-scanning/get-managed-analysis-info" },
      ].map { |c| c.merge(options: { persist_with: :turboscan }) }

      VCR.use_cassettes(cassettes) do
        VCR.use_cassette("code-scanning/managed-analyses-update", persist_with: :turboscan, allow_unused_http_interactions: false) do
          result = SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { query_suite: "extended" }]])
          assert_nil result.error
        end
      end
    end

    test "any action other than update or onboard raises an error" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      assert_raises(ArgumentError) do
        SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :something_else, languages: ["ruby"] }]])
      end
    end

    skus_test "there is no error if auto codeql was successfully disabled for repo" do
      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      Turbocassette.use("code-scanning/managed-analyses-disable") do
        assert_nil SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_disable: [:auto_codeql]).error
      end
    end

    skus_test "Disable YML workflow after enable call", skip_enterprise: true do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      @public_repo.update(languages: [@python, @ruby, @js])
      example_repo :code_scanning_alerts_for_every_language, @public_repo
      # Create a workflow file that matches the repository data within git
      workflow = create(:workflow, repository: @public_repo, path: ".github/workflows/codeql.yml")
      workflow.present_in_default_branch = true
      workflow.save
      workflow.reload
      workflow.update(state: "active")

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        %w[actions javascript-typescript python ruby].all? do
          |lang| request[:supported_languages].include?(lang)
        end
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      travel_to Time.zone.parse("0001-01-01 00:00:00") do
        VCR.use_cassette("code-scanning/get-tool-status-messages", persist_with: :turboscan) do
          assert_nil SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
        end
      end
      workflow.reload
      refute workflow.active?
    end

    skus_test "Handles yaml workflow already disabled", skip_enterprise: true do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      @public_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_repo

      # Create a workflow file
      workflow = create(:workflow, repository: @public_repo, path: ".github/workflows/w1.yml")
      workflow.present_in_default_branch = true
      workflow.save
      workflow.reload
      workflow.disable(@user)

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        %w[actions javascript-typescript python ruby].all? do
          |lang| request[:supported_languages].include?(lang)
        end
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-tool-status-blank", persist_with: :turboscan) do
        assert_nil SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
      end
    end

    test "Send the correct global id to turboscan" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      # on enterprise use the old global id
      if GitHub.enterprise?
        repo_global_id = @public_org_repo.global_relay_id
        enabled_by_actor_grid = @user.global_relay_id
      else
        repo_global_id = @public_org_repo.next_global_id
        enabled_by_actor_grid = @user.next_global_id
      end

      body_params_matcher = lambda do |actual, expected|
        actual_body = JSON.parse(actual.body)
        expected_body = JSON.parse(expected.body)
        actual_body.slice("globalRepositoryId", "enabledByActorGrid") == { "globalRepositoryId" => repo_global_id, "enabledByActorGrid" => enabled_by_actor_grid }
      end

      VCR.use_cassette("code-scanning/get-tool-status-blank", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-enable", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
          assert_nil SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
        end
      end
    end
  end

  context "enable Auto CodeQL for Java-Kotlin" do
    skus_test "Repo with Only Java sends has_kotlin false" do
      @private_repo.update(languages: [@java])

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.expects(:dismiss_yml).returns(true)
      auto_codeql.actions_runner_checker.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        request[:has_kotlin] == false
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
        assert_nil auto_codeql.on_enable(actor: @user, options: { action: :enable }).error
      end
    end

    skus_test "Repo with Only Kotlin sends has_kotlin true" do
      @private_repo.update(languages: [@kotlin])

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.expects(:dismiss_yml).returns(true)
      auto_codeql.actions_runner_checker.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        request[:has_kotlin] == true
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
        assert_nil auto_codeql.on_enable(actor: @user, options: { action: :enable }).error
      end
    end

    skus_test "Repo with Java and Kotlin sends has_kotlin true" do
      @private_repo.update(languages: [@java, @kotlin])

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.expects(:dismiss_yml).returns(true)
      auto_codeql.actions_runner_checker.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        request[:has_kotlin] == true
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
        assert_nil auto_codeql.on_enable(actor: @user, options: { action: :enable }).error
      end
    end
  end

  context "audit log events" do
    skus_test "event for successfully enabled public (dotcom) repo", skip_enterprise: true do
      @public_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_enabled"

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      CodeScanning::AutoCodeql.any_instance.expects(:dismiss_yml).returns(true)

      Turbocassette.use("code-scanning/managed-analyses-enable") do
        SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]])
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @public_repo.nwo,
        repo_id: @public_repo.id,
        public_repo: true,
        query_suite: "default",
        threat_model: "remote",
        languages: %w[javascript-typescript python ruby],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "event for successfully enabled public org-owned repo" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_enabled"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      CodeScanning::AutoCodeql.any_instance.expects(:dismiss_yml).returns(true)

      cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        Turbocassette.use(cassette) do
          assert_nil SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
        end
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @public_org_repo.nwo,
        repo_id: @public_org_repo.id,
        public_repo: true,
        org: @org.login,
        org_id: @org.id,
        query_suite: "default",
        threat_model: "remote",
        languages: %w[javascript-typescript python ruby],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "event for successfully enabled private repo" do
      @private_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @private_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_enabled"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      CodeScanning::AutoCodeql.any_instance.expects(:dismiss_yml).returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

      cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
      Turbocassette.use(cassette) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]]).error
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @private_repo.nwo,
        repo_id: @private_repo.id,
        public_repo: false,
        org: @org.login,
        org_id: @org.id,
        query_suite: "default",
        threat_model: "remote",
        languages: %w[javascript-typescript python ruby],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "there is no event when trying to enable a repo that is already enabled" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      onboard_events = subscribe "repo.codeql_enabled"
      update_events = subscribe "repo.codeql_updated"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-enable-noop", persist_with: :turboscan) do
          SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :enable }]])
        end
      end

      refute onboard_events.pop, "an onboard event isn't expected"
      refute update_events.pop, "an update event isn't expected"
    end

    skus_test "event for successfully updated for public (dotcom) repo", skip_enterprise: true do
      @public_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_updated"

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
        SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]])
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @public_repo.nwo,
        repo_id: @public_repo.id,
        public_repo: true,
        languages: ["ruby"],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "event for successfully updated public org-owned repo" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_updated"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
          SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]])
        end
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @public_org_repo.nwo,
        repo_id: @public_org_repo.id,
        public_repo: true,
        org: @public_org_repo.owner.display_login,
        org_id: @public_org_repo.owner.id,
        languages: ["ruby"],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "event for successfully updated private repo" do
      @private_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @private_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      events = subscribe "repo.codeql_updated"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/managed-analyses-update-ruby", persist_with: :turboscan) do
        SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]])
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @private_repo.nwo,
        repo_id: @private_repo.id,
        public_repo: false,
        org: @private_repo.owner.login,
        org_id: @private_repo.owner.id,
        languages: ["ruby"],
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "there is no event when a noop update is submitted" do
      @public_org_repo.update(languages: [@python, @ruby, @js])
      example_repo :branch_escape, @public_org_repo

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      onboard_events = subscribe "repo.codeql_enabled"
      update_events = subscribe "repo.codeql_updated"

      CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once.returns(SecurityProduct::Result.new(true))

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      VCR.use_cassette("code-scanning/counts-absent", persist_with: :turboscan) do
        VCR.use_cassette("code-scanning/managed-analyses-update-noop", persist_with: :turboscan) do
          SecurityProduct::ServiceManager.new(@public_org_repo).toggle_services(@user, services_to_enable: [[:auto_codeql, { action: :update, languages: ["ruby"] }]])
        end
      end

      refute onboard_events.pop, "an onboard event isn't expected"
      refute update_events.pop, "an update event isn't expected"
    end

    skus_test "event for successfully disabled for repo" do
      events = subscribe "repo.codeql_disabled"

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      Turbocassette.use("code-scanning/managed-analyses-disable") do
        SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_disable: [:auto_codeql])
      end

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        repo: @public_repo.nwo,
        repo_id: @public_repo.id,
        public_repo: true
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    skus_test "there is no event when trying to disable a repo that is already disabled" do
      events = subscribe "repo.codeql_disabled"

      # Security Center uses the repo serialization code to compare how the enablement of security products has
      # changed. This means that in some cases this calls `get_managed_analysis_info` even if our logic would not
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

      Turbocassette.use("code-scanning/managed-analyses-disable-noop") do
        SecurityProduct::ServiceManager.new(@public_repo).toggle_services(@user, services_to_disable: [:auto_codeql])
      end

      refute events.pop, "an event was not expected"
    end
  end

  context "can_enable Auto CodeQL" do
    skus_test "returns true if all conditions are met" do
      @private_repo.update(languages: [@ruby])
      CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

      can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})

      assert_equal true, can_enable.value
    end

    skus_test "returns true if all conditions are met with no CodeQL language" do
      @private_repo.update(languages: [@bash])
      CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

      can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})

      assert_equal true, can_enable.value
    end

    skus_test "returns false if code scanning is disabled" do
      GitHub.stubs(:code_scanning_enabled?).returns(false)
      @private_repo.update(languages: [@ruby])
      can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})

      assert_equal :code_scanning_not_available, can_enable.error
    end

    skus_test "returns false if service is disabled" do
      service = split_sku_test? ? :code_security : :advanced_security
      SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@user, services_to_disable: [[service, { force?: true }]])

      can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})

      assert_equal "#{service}_disabled".to_sym, can_enable.error
    end

    skus_test "returns false if Actions are disabled" do
      @private_repo.disable_actions(actor: @user)
      can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})

      assert_equal :repo_actions_disabled, can_enable.error
    end

    context "languages" do
      skus_test "returns true if no supported AutoCodeQL language is present" do
        @private_repo.update(languages: [@bash])

        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})
        advanced_security_enabled = SecurityProduct::AdvancedSecurity.new(@private_repo).enabled?

        assert_equal true, can_enable.value
      end


      skus_test "returns true if a recommended AutoCodeQL language is present" do
        @private_repo.update(languages: [@bash, @ruby])

        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})
        advanced_security_enabled = SecurityProduct::AdvancedSecurity.new(@private_repo).enabled?

        assert_equal true, can_enable.value
      end

      skus_test "returns true if a not recommended languages is present " do
        @private_repo.update(languages: [@bash, @ruby, @java])

        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})
        advanced_security_enabled = SecurityProduct::AdvancedSecurity.new(@private_repo).enabled?

        assert_equal true, can_enable.value
      end

      skus_test "returns true if a supported language is present" do
        @private_repo.update(languages: [@bash, @java])

        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: {})
        advanced_security_enabled = SecurityProduct::AdvancedSecurity.new(@private_repo).enabled?

        assert_equal true, can_enable.value
      end
    end

    skus_test "returns false for archived repositories", skip_enterprise: true do
      # GHAS is required on public repos on Enterprise and GHAS is automatically disabled for archived repositories,
      # so this case would have been caught by the GHAS condition
      @public_org_repo.set_archived

      can_enable = CodeScanning::AutoCodeql.new(@public_org_repo).can_enable?(actor: @user, options: {})

      assert_equal :repo_archived, can_enable.error
    end

    skus_test "returns true if repo has no existing analysis and option to fail is supplied" do
      example_repo :branch_escape, @private_repo
      @private_repo.update(languages: [@js])

      CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

      VCR.use_cassette("code-scanning/get-tool-status-messages-outdated", persist_with: :turboscan) do
        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: { fail_on_manual_workflow?: true })
        assert_equal true, can_enable.value
      end
    end

    skus_test "returns true if repo has an advanced setup analysis that is older than 90 days and option to fail is supplied" do
      example_repo :branch_escape, @private_repo
      @private_repo.update(languages: [@js])

      CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

      VCR.use_cassette("code-scanning/get-tool-status-messages-blank", persist_with: :turboscan) do
        can_enable = CodeScanning::AutoCodeql.new(@private_repo).can_enable?(actor: @user, options: { fail_on_manual_workflow?: true })
        assert can_enable
        assert_nil can_enable.error
      end
    end
  end

  context "self-hosted runners flag" do
    skus_test "flag is set if code-scanning labelled runners are available" do
      @private_repo.update(languages: [@ruby])

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(true)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.expects(:dismiss_yml).returns(true)

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with(has_entries(
        runner_label: "code-scanning")
      ).returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
        auto_codeql.on_enable(actor: @user, options: { action: :enable })
      end
    end

    skus_test "flag is not set if no code-scanning labelled runners are available", skip_enterprise: true do
      @private_repo.update(languages: [@ruby])
      # SecurityProductsEnablement::Actions::RunnerChecker#labelled_runners_available? is stubbed to false in setup

      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.expects(:dismiss_yml).returns(true)

      GitHub::Turboscan::ManagedAnalyses.expects(:enable).with do |request|
        !request.has_key?(:runner_label)
      end.returns(::Twirp::ClientResp.new(data: Turboscan::Proto::EnableResponse.new, error: nil))

      VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
        auto_codeql.on_enable(actor: @user, options: { action: :enable })
      end
    end
  end

  skus_test "retrieve consistent data from Turboscan" do
    example_repo :branch_escape, @private_repo
    # Define these languages for consistency with the cassettes
    @private_repo.update(languages: [@python, @ruby, @js])

    make_trusted_oauth_apps_owner
    launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(launch_app)

    auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
    auto_codeql.expects(:dismiss_yml).returns(true)
    auto_codeql.actions_runner_checker.expects(:labelled_runners_available?).once.returns(true) if GitHub.enterprise?

    Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
      refute auto_codeql.enabled?
    end

    cassette = GitHub.enterprise? ? "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label" : "code-scanning/managed-analyses-enable"
    Turbocassette.use(cassette) do
      assert_nil auto_codeql.on_enable(actor: @user, options: {}).error
    end

    # The next call should return the enabling status.
    auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
    Turbocassette.use("code-scanning/get-managed-analysis-info-onboarding") do
      assert auto_codeql.enabling?
    end

    # After the validation run completes the status should be enabled
    auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
    Turbocassette.use("code-scanning/get-managed-analysis-info-stable") do
      assert auto_codeql.enabled?
    end

    auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
    Turbocassette.use("code-scanning/get-managed-analysis-info-waiting-onboarding-failed") do
      assert auto_codeql.enabled?
      # MG: This is called "disabled reason" but the state here would be waiting.
      # Do we actually use this method, can we drop it?
      # It seems we only use it in `auto_codeql_failed?`.
      assert_equal "Workflow run has failed", auto_codeql.disabled_reason
    end
  end

  context "enabled?" do
    skus_test "returns true if autocodeql and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info") do
        assert auto_codeql.enabled?
      end
    end

    skus_test "returns false if autocodeql is not enabled and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
        assert_equal false, auto_codeql.enabled?
      end
    end

    skus_test "returns true if autocodeql is onboarding and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabling") do
        assert_equal true, auto_codeql.enabled?
      end
    end

    skus_test "returns false if autocodeql is enabled and actions are not enabled" do
      @private_repo.disable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info") do
        assert_equal false, auto_codeql.enabled?
      end
    end

    skus_test "returns true if autocodeql is enabled and a config update is in progress" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabled-updating") do
        assert_equal true, auto_codeql.enabled?
      end
    end

    skus_test "returns true if autocodeql is enabled and a config update or template upgrade has failed" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabled-failed-update") do
        assert_equal true, auto_codeql.enabled?
      end
    end
  end

  context "updating?" do
    skus_test "returns true if autocodeql is enabled and a config update is in progress" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabled-updating") do
        assert_equal true, auto_codeql.updating?
      end
    end
  end

  context "waiting?" do
    skus_test "returns true if autocodeql is in a waiting state" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-waiting") do
        assert_equal true, auto_codeql.waiting?
      end
    end
  end

  context "disabled?" do
    skus_test "returns false if autocodeql and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info") do
        assert_equal false, auto_codeql.disabled?
      end
    end

    skus_test "returns true if autocodeql is not enabled and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
        assert_equal true, auto_codeql.disabled?
      end
    end

    skus_test "returns false if autocodeql is enabling and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabling") do
        assert_equal false, auto_codeql.disabled?
      end
    end

    skus_test "returns true if autocodeql is enabled and actions are not enabled" do
      @private_repo.disable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info") do
        assert_equal true, auto_codeql.disabled?
      end
    end
  end

  context "enabling?" do
    skus_test "returns false if autocodeql and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info") do
        assert_equal false, auto_codeql.enabling?
      end
    end

    skus_test "returns false if autocodeql is not enabled and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
        assert_equal false, auto_codeql.enabling?
      end
    end

    skus_test "returns true if autocodeql is enabling and actions are enabled" do
      @private_repo.enable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabling") do
        assert_equal true, auto_codeql.enabling?
      end
    end

    skus_test "returns false if autocodeql is enabling and actions are not enabled" do
      @private_repo.disable_actions(actor: @user)
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      Turbocassette.use("code-scanning/get-managed-analysis-info-enabling") do
        assert_equal false, auto_codeql.enabling?
      end
    end
  end

  context "configuration" do
    skus_test "returns the active configuration if default setup is configured" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      config = Turbocassette.use("code-scanning/get-managed-analysis-info") do
        auto_codeql.configuration
      end

      assert_equal "configured", config.state
      assert_equal %w[javascript-typescript python ruby], config.languages
      assert_equal "default", config.query_suite
      assert_equal "remote", config.threat_model
      assert_equal "weekly", config.schedule
    end

    skus_test "returns an empty configuration if default setup is not configured" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      config = Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
        auto_codeql.configuration
      end

      assert_equal "not-configured", config.state
      assert_equal [], config.languages
      assert_nil config.query_suite
      assert_nil config.threat_model
      assert_nil config.schedule
    end

    skus_test "returns a configuration if default setup is waiting" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      config = Turbocassette.use("code-scanning/get-managed-analysis-info-waiting") do
        auto_codeql.configuration
      end

      assert_equal "configured", config.state
      assert_equal [], config.languages
      assert_equal "default", config.query_suite
      assert_equal "remote", config.threat_model
      assert_nil config.schedule
    end
  end

  context "adjust_configuration" do
    skus_test "adjust configuration languages does not error when successful" do
      @private_repo.update(languages: [@python, @ruby, @js])
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      VCR.use_cassette("code-scanning/managed-analyses-adjust", persist_with: :turboscan) do
        result = auto_codeql.adjust_configuration(%w[javascript-typescript python])
        refute result.error?
      end
    end

    skus_test "adjust configuration returns an error when turboscan fails" do
      @private_repo.update(languages: [@python, @ruby, @js])
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      VCR.use_cassette("code-scanning/managed-analyses-adjust-error", persist_with: :turboscan) do
        result = auto_codeql.adjust_configuration(%w[javascript-typescript python])
        assert result.error?
      end
    end

    skus_test "adjust configuration correctly converts to combined languages" do
      @private_repo.update(languages: [@java, @cpp])
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      GitHub::Turboscan::ManagedAnalyses.expects(:adjust).with(
        {
          repository_id: @private_repo.id,
          owner_id: @private_repo.owner_id,
          languages: %w[java-kotlin c-cpp],
          workflow_run_id: 0
        }
      ).once.returns(::Twirp::ClientResp.new(data: ::Turboscan::Proto::AdjustResponse.new({}), error: nil))

      result = auto_codeql.adjust_configuration(%w[java cpp])
      refute result.error?
    end
  end

  context "recommended_configuration" do
    skus_test "returns the recommended configuration" do
      @private_repo.update(languages: [@bash, @js, @java])
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      config = auto_codeql.recommended_configuration

      assert_equal "not-configured", config.state
      assert_equal %w[java-kotlin javascript-typescript], config.languages
      assert_equal "default", config.query_suite
      assert_equal "remote", config.threat_model
    end
  end

  context "dismiss notice" do
    skus_test "the notice is not dismissed for a new failure" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      # we dismiss notice for the run 4, it should be dismissed
      auto_codeql.stubs(:debuggable_auto_codeql_run_id).returns("4")
      auto_codeql.dismiss_auto_codeql_notice(repository_id: @private_repo.id, user_id: @user.id)
      dismissed = auto_codeql.dismissed_auto_codeql_notice?(repository_id: @private_repo.id, user_id: @user.id)
      assert_equal true, dismissed

      # we get another run, run 5, notice should not be dismissed
      Turbocassette.use("code-scanning/get-managed-analysis-info-waiting-onboarding-failed") do
        auto_codeql.stubs(:debuggable_auto_codeql_run_id).returns("5")
        dismissed = auto_codeql.dismissed_auto_codeql_notice?(repository_id: @private_repo.id, user_id: @user.id)
        refute dismissed
      end
    end

    skus_test "user will see set up error banner if dismissed by another person" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)

      Turbocassette.use("code-scanning/get-managed-analysis-info-waiting-onboarding-failed") do
        auto_codeql.dismiss_auto_codeql_notice(repository_id: @private_repo.id, user_id: 7)

        # check if the notice is dismissed for user who dismissed it
        dismissed_user_7 = auto_codeql.dismissed_auto_codeql_notice?(repository_id: @private_repo.id, user_id: 7)
        assert_equal true, dismissed_user_7

        # check if the notice is dismissed for user who did not dismiss it
        dismissed_user_1 = auto_codeql.dismissed_auto_codeql_notice?(repository_id: @private_repo.id, user_id: 1)
        refute dismissed_user_1
      end
    end

    skus_test "dismissing when there's no notice doesn't raise" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      auto_codeql.stubs(:debuggable_auto_codeql_run_id).returns(nil)

      assert_nothing_raised do
        auto_codeql.dismiss_auto_codeql_notice(repository_id: @private_repo.id, user_id: @user.id)
      end
    end
  end

  context "#active_query_suite" do
    skus_test "returns query suite when configured" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      %w[default extended].each do |suite|
        config = CodeScanning::AutoCodeqlConfig.new(
          state: "configured",
          languages: [],
          query_suite: suite,
          threat_model: nil,
          updated_at: nil,
          schedule: nil,
          initial_languages: [],
          creation_trigger: :MANUAL,
          runner_label: nil
        )
        auto_codeql.stubs(:configuration).returns(config)

        assert_equal suite, auto_codeql.active_query_suite
      end
    end

    skus_test "returns nil when not configured" do
      auto_codeql = CodeScanning::AutoCodeql.new(@private_repo)
      %w[default extended].each do |suite|
        config = CodeScanning::AutoCodeqlConfig.new(
          state: "not-configured",
          languages: [],
          query_suite: suite,
          threat_model: nil,
          updated_at: nil,
          schedule: nil,
          initial_languages: [],
          creation_trigger: nil,
          runner_label: nil
        )
        auto_codeql.stubs(:configuration).returns(config)

        assert_nil auto_codeql.active_query_suite
      end
    end
  end
end
