# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_graph_helpers"
require "test_helpers/innersource_helper"
require "test_helpers/private_token_scanning_test_helper"

class RepositorySecurityProductsDependencyTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include InnersourceHelper
  include PlatformTestHelpers::InterfaceHelpers
  include TurboghasHelpers
  include SecurityProductsEnablementHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  extend T::Sig

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @owner = create(:user)
    @business = create(:global_business)
    @org = T.must(T.let(create(:organization, admin: @owner, business: @business), ::Organization))

    @other_org = T.must(T.let(create(:organization, admin: @owner, business: @business), ::Organization))

    @repo = T.must(T.let(create(:repository, owner: @org), ::Repository))

    # Using GraphQL for creating a repo without using factorybot
    # This creation path goes through `setup_security_products_on_creation` for the tests that care.
    @create_repo_mutation = create_repo_graphql_mutation
  end

  setup do
    skip_force_api_test_origin
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable

    @security_configuration = create(:security_configuration,
      :default_for_new_repos,
      target: @org,
      enable_ghas: true,
      dependency_graph: "disabled",
      dependabot_alerts: "disabled",
      dependabot_security_updates: "disabled",
      code_scanning: "not_set",
    )
  end

  context "for repo creation" do
    test "fires backfill request for secret scanning" do
      # We're relying on security feature enablement/disablement to fire these events since we didn't instrument repo create.
      # For this test that means if the setting to enable secret scanning by default for new private repos
      # is enabled, then during repo creation the event will fire.
      reset_hydro

      @org.enable_advanced_security_on_new_repos(actor: @owner)
      SecretScanning::Features::Org::TokenScanning.new(@org).enable_secret_scanning_for_new_repos(actor: @owner)

      assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

      input = {
        "name" => "FancyOrgRepo",
        "ownerId" => @org.global_relay_id,
        "visibility" => "PRIVATE",
      }

      # Using GraphQL for creating a repo so we go through the `SecurityProductsDependency#setup_security_products_on_creation` path
      assert_difference("@org.repositories.count") do
        perform_required_enablement_jobs do
          execute_query(@create_repo_mutation, viewer: @owner, "$input": input).data
        end
      end

      assert_hydro_published_partial({
        type: :START,
        actor: Hydro::EntitySerializer.user(@owner),
        repo_scope: {
          repo: Hydro::EntitySerializer.repository(@org.repositories.last),
          owner: Hydro::EntitySerializer.user(@org),
        },
      }, schema: "token_scanning_service.v0.BackfillRequest")
    end

    test "enables secret scanning and push protections" do
      @org.enable_advanced_security_on_new_repos(actor: @owner)
      SecretScanning::Features::Org::TokenScanning.new(@org).enable_secret_scanning_for_new_repos(actor: @owner)
      SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor: @owner)

      assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

      input = {
        "name" => "FancyOrgRepo",
        "ownerId" => @org.global_relay_id,
        "visibility" => "PRIVATE",
      }

      # Using GraphQL for creating a repo so we go through the `SecurityProductsDependency#setup_security_products_on_creation` path
      assert_difference("@org.repositories.count") do
        perform_required_enablement_jobs do
          execute_query(@create_repo_mutation, viewer: @owner, "$input": input).data
        end
      end

      assert SecretScanning::Features::Repo::TokenScanning.new(@org.repositories.last).enabled?
      assert SecretScanning::Features::Repo::PushProtection.new(@org.repositories.last).enabled?
    end

    test "enables ghas and secret scanning on a GHES instance with dependency graph" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:security_alerts_enabled_for_new_repos?).returns(false)
      Organization.any_instance.stubs(:vulnerability_updates_enabled_for_new_repos?).returns(false)
      Organization.any_instance.stubs(:advanced_security_enabled_on_new_repos?).returns(true)
      GitHub.stubs(:dependency_graph_enabled?).returns(true)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_scanning_enabled_for_new_repos?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

      result = perform_required_enablement_jobs do
        create_repository(user:  @owner, owner: @org.login)
      end

      repo_token_scanning = SecretScanning::Features::Repo::TokenScanning.new(result.repository)
      assert repo_token_scanning.enabled?
      if GitHub.enterprise?
        assert result.repository.advanced_security_enabled?
      end
    end

    context "with a free public repo", skip_enterprise: true do
      test "secret-scanning is always enabled" do
        rando = create(:user)
        # This option does not matter for free users!!
        # Disabling it should have no effect on the end result.
        SecretScanning::Features::User::TokenScanning.new(rando).disable_secret_scanning_for_new_repos(actor: rando)

        # Feature is not available at the **user** level
        refute SecretScanning::Features::User::TokenScanning.new(rando).feature_available?
        result = create_repository(user:  rando, owner: rando.display_login, private: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end

      test "push-protection is auto-enabled" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable
        rando = create(:user)
        SecretScanning::Features::User::PushProtection.new(rando).enable_for_new_repos(actor: rando)

        # Feature is not available at the **user** level
        refute SecretScanning::Features::User::TokenScanning.new(rando).feature_available?
        assert SecretScanning::Features::User::PushProtection.new(rando).enabled_for_new_repos?

        result = create_repository(user:  rando, owner: rando.display_login, private: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
      end
    end

    context "with a user on GHES", enterprise_only: true do
      test "defers to business to enable ghas + secret scanning" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.enable_advanced_security_on_new_user_namespace_repos(actor: @owner)

        rando = create(:user)
        # business checked; user not checked
        SecretScanning::Features::Business::TokenScanning.new(@business).enable_secret_scanning_for_new_repos(actor: @owner)
        SecretScanning::Features::User::TokenScanning.new(rando).disable_secret_scanning_for_new_repos(actor: rando)

        result = create_repository(user:  rando, owner: rando.display_login, public: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end

      test "falls back to user settings" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.enable_advanced_security_on_new_user_namespace_repos(actor: @owner)

        rando = create(:user)
        # business not checked; user checked
        SecretScanning::Features::Business::TokenScanning.new(@business).disable_secret_scanning_for_new_repos(actor: @owner)
        SecretScanning::Features::User::TokenScanning.new(rando).enable_secret_scanning_for_new_repos(actor: rando)

        result = create_repository(user:  rando, owner: rando.display_login, public: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end
    end

    context "with an enterprise managed user", skip_enterprise: true do
      test "defers to business to enable ghas + secret scanning" do
        emu_biz = create(:business, :enterprise_managed)
        emu_owner = emu_biz.owners.first
        emu_biz.mark_advanced_security_as_purchased_for_entity(actor: emu_owner)
        emu_biz.enable_advanced_security_on_new_user_namespace_repos(actor: emu_owner)

        emu_user = create(:emu, business: emu_biz)
        # business checked; user not checked
        SecretScanning::Features::Business::TokenScanning.new(emu_biz).enable_secret_scanning_for_new_repos(actor: emu_owner)
        SecretScanning::Features::User::TokenScanning.new(emu_user).disable_secret_scanning_for_new_repos(actor: emu_owner)

        assert SecretScanning::Features::User::TokenScanning.new(emu_user).feature_available?
        result = create_repository(user:  emu_user, owner: emu_user.display_login, public: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end

      test "falls back to user settings" do
        emu_biz = create(:business, :enterprise_managed)
        emu_owner = emu_biz.owners.first
        emu_biz.mark_advanced_security_as_purchased_for_entity(actor: emu_owner)
        emu_biz.enable_advanced_security_on_new_user_namespace_repos(actor: emu_owner)

        emu_user = create(:emu, business: emu_biz)
        # business not checked; user checked
        SecretScanning::Features::Business::TokenScanning.new(emu_biz).disable_secret_scanning_for_new_repos(actor: emu_owner)
        SecretScanning::Features::User::TokenScanning.new(emu_user).enable_secret_scanning_for_new_repos(actor: emu_owner)

        assert SecretScanning::Features::User::TokenScanning.new(emu_user).feature_available?
        result = create_repository(user:  emu_user, owner: emu_user.display_login, public: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end

      test "can enable push-protection if set to auto-enable by the user" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable

        emu_biz = create(:business, :enterprise_managed)
        emu_owner = emu_biz.owners.first
        emu_biz.mark_advanced_security_as_purchased_for_entity(actor: emu_owner)
        emu_biz.enable_advanced_security_on_new_user_namespace_repos(actor: emu_owner)

        emu_user = create(:emu, business: emu_biz)
        SecretScanning::Features::Business::TokenScanning.new(emu_biz).enable_secret_scanning_for_new_repos(actor: emu_owner)
        SecretScanning::Features::Business::PushProtection.new(emu_biz).enable_for_new_repos(actor: emu_owner)

        assert SecretScanning::Features::Business::PushProtection.new(emu_biz).enabled_for_new_repos?

        result = create_repository(user:  emu_user, owner: emu_user.display_login, public: false)
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
      end
    end

    context "with a ghas organization", skip_enterprise: true do
      test "enables secret scanning without disabling dependabot/dependency graph when creating a private repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "enables secret scanning & push protections without disabling dependabot/dependency graph when creating a private repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "enables secret scanning & push protections without disabling dependabot/dependency graph when creating a public repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: false)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "enables secret scanning without disabling dependabot/dependency graph when creating a public repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: false)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "only enables public repositories when GHAS is purchased, but not automatically enabled for new repositories", skip_enterprise: true do
        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: false)
        end
        assert_predicate result, :success?

        repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end
    end

    context "with a non-ghas organization", skip_enterprise: true do
      test "enables secret scanning without disabling dependabot/dependency graph when creating a public repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        # enables secret scanning for public repos
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: false)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "does not enable secret scanning & push protections without disabling dependabot/dependency graph when creating a private repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        refute SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        refute SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end

      test "does not enable secret scanning without disabling dependabot/dependency graph when creating a private repo", skip_enterprise: true do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled"
        )
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor:  @owner)
        @org.enable_dependabot_on_actions_for_new_repos(actor:  @owner)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @owner)
        @org.enable_dependabot_autofix_for_new_repos(actor: @owner)

        assert SecretScanning::Features::Org::TokenScanning.new(@org.reload).feature_available?

        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        repo = result.repository

        assert repo.vulnerability_alerts_enabled?
        refute SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        assert @org.vulnerability_updates_grouping_enabled_for_new_repos?
        assert @org.dependabot_on_actions_enabled_for_new_repos?
        assert @org.dependabot_self_hosted_enabled_for_new_repos?
        assert @org.dependabot_autofix_enabled_for_new_repos?
      end
    end

    context "enables dependabot per org settings", skip_enterprise: true do
      test "enables dependabot", skip_enterprise: true do
        @security_configuration.update(
          dependency_graph: "enabled",
          dependabot_alerts: "enabled",
        )
        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        repo = result.repository
        assert repo.vulnerability_alerts_enabled?
      end
    end

    context "configures innersource advisories per org settings" do
      test "enables innersource advisories" do
        enable_innersource
        @org.enable_innersource_advisories_for_new_repos(actor: @owner)
        result = create_repository(user: @owner, owner: @org.login, private: true)
        assert_predicate result, :success?

        assert result.repository.innersource_advisories_enabled?
      end

      test "disables innersource advisories" do
        enable_innersource
        Repository.any_instance.unstub(:innersource_advisories_enabled?)

        @security_configuration.update(private_vulnerability_reporting: "disabled")
        result = perform_required_enablement_jobs do
          create_repository(user:  @owner, owner: @org.login, private: true)
        end
        assert_predicate result, :success?

        refute result.repository.innersource_advisories_enabled?
      end
    end

    context "#get_secret_scanning_options" do
      test "returns the business-level default when security configurations are enabled for the org" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enable

        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.enable_advanced_security_on_new_repos(actor: @owner)
        SecretScanning::Features::Business::TokenScanning.new(@business).enable_secret_scanning_for_new_repos(actor: @owner)
        SecretScanning::Features::Business::ValidityChecks.new(@business).enable_for_new_repos(actor: @owner)

        repo = create(:private_repository, owner: @org)
        results = repo.send(:get_secret_scanning_options)

        expected_results = { token_scanning_enabled: "1" }
        expected_results[:token_scanning_validity_checks_enabled] = "1" unless GitHub.single_or_multi_tenant_enterprise? # Validity checks are only available in Dotcom
        assert_equal expected_results, results
      end
    end
  end

  context "for repo creation as a fork" do
    context "when forking into an enterprise managed user account", skip_enterprise: true do
      test "enables advanced security + secret scanning for org -> user" do
        mt_biz = create(:business, :enterprise_managed)
        mt_owner = mt_biz.owners.first
        mt_biz.mark_advanced_security_as_purchased_for_entity(actor: mt_owner)
        mt_biz.enable_advanced_security_on_new_user_namespace_repos(actor: mt_owner)
        mt_biz.allow_private_repository_forking(actor: mt_owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

        # business checked; user not checked
        SecretScanning::Features::Business::TokenScanning.new(mt_biz).enable_secret_scanning_for_new_repos(actor: mt_owner)

        # Destination owner
        dest_owner = create(:emu, business: mt_biz)

        # Source owner
        src_owner = create(:organization, admin: mt_owner, business: mt_biz)
        src_owner.add_admin(dest_owner)
        repo = create(:private_repository, owner: src_owner)

        result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          fork_repository(repo:, dest_owner:)
        end
        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
      end

      test "falls back to user settings" do
        mt_biz = create(:business, :enterprise_managed)
        mt_owner = mt_biz.owners.first
        mt_biz.mark_advanced_security_as_purchased_for_entity(actor: mt_owner)
        mt_biz.enable_advanced_security_on_new_user_namespace_repos(actor: mt_owner)
        mt_biz.allow_private_repository_forking(actor: mt_owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

        # Destination owner
        dest_owner = create(:emu, business: mt_biz)
        # business not checked; user checked
        SecretScanning::Features::Business::TokenScanning.new(mt_biz).disable_secret_scanning_for_new_repos(actor: mt_owner)
        SecretScanning::Features::User::TokenScanning.new(dest_owner).enable_secret_scanning_for_new_repos(actor: dest_owner)

        # Source owner
        src_owner = create(:organization, admin: mt_owner, business: mt_biz)
        src_owner.add_admin(dest_owner)
        repo = create(:private_repository, owner: src_owner)

        result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          fork_repository(repo:, dest_owner:)
        end
        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
      end
    end

    context "when forking into a user account", skip_enterprise: true do
      test "auto-enables secret scanning and push protection if repo is public" do
        # These flags are at 100%, so going to just assume they are enabled
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable

        # Destination owner
        dest_owner = create(:user)

        # Source owner
        src_owner = create(:user)
        repo = create(:public_repository, owner: src_owner)

        result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          fork_repository(repo:, dest_owner:)
        end
        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(new_repo).enabled?
      end

      test "does not auto-enable secret scanning and push protection if repo is private" do
        # These flags are at 100%, so going to just assume they are enabled
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable

        # Destination owner
        dest_owner = create(:user)

        # Source owner
        src_owner = create(:organization, admin: dest_owner)
        src_owner.allow_private_repository_forking(actor: dest_owner)
        repo = create(:private_repository, owner: src_owner)

        result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          fork_repository(repo:, dest_owner:)
        end
        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        refute SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
        refute SecretScanning::Features::Repo::PushProtection.new(new_repo).enabled?
      end
    end

    context "when forking into a user account on GHES", enterprise_only: true do
      test "defers to business to enable ghas + secret scanning" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.enable_advanced_security_on_new_user_namespace_repos(actor: @owner)
        @business.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

        # Destination owner
        dest_owner = create(:user)

        # business checked; user not checked
        SecretScanning::Features::Business::TokenScanning.new(@business).enable_secret_scanning_for_new_repos(actor: @owner)
        SecretScanning::Features::User::TokenScanning.new(dest_owner).disable_secret_scanning_for_new_repos(actor: dest_owner)

        # Source owner
        src_owner = create(:organization, admin: @owner, business: @business)
        src_owner.add_admin(dest_owner)
        repo = create(:private_repository, owner: src_owner)

        result = perform_required_enablement_jobs do
          fork_repository(repo:, dest_owner:)
        end

        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
      end

      test "falls back to user settings" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.enable_advanced_security_on_new_user_namespace_repos(actor: @owner)
        @business.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

        # Destination owner
        dest_owner = create(:user)

        # business checked; user not checked
        SecretScanning::Features::Business::TokenScanning.new(@business).disable_secret_scanning_for_new_repos(actor: @owner)
        SecretScanning::Features::User::TokenScanning.new(dest_owner).enable_secret_scanning_for_new_repos(actor: dest_owner)

        # Source owner
        src_owner = create(:organization, admin: @owner, business: @business)
        src_owner.add_admin(dest_owner)
        repo = create(:private_repository, owner: src_owner)

        result = perform_required_enablement_jobs do
          fork_repository(repo:, dest_owner:)
        end

        assert_equal :succeeded, result.state.to_sym

        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
      end
    end

    context "when forking into an organization" do
      test "follows orgs settings" do
        # These flags are at 100%, so going to just assume they are enabled
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable

        @org.enable_advanced_security_on_new_repos(actor: @owner)
        SecretScanning::Features::Org::TokenScanning.new(@org).enable_secret_scanning_for_new_repos(actor:  @owner)
        SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor:  @owner)

        @business.allow_private_repository_forking(force: true, actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
        @org.allow_private_repository_forking(force: true, actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

        # Destination owner
        dest_owner = @org

        # Source owner same as destination owner to ease permissions
        # to create repos in org

        repo = perform_required_enablement_jobs do
          create(:public_repository, owner: @owner)
        end

        result = perform_required_enablement_jobs do
          fork_repository(repo:, dest_owner:, forker: @owner)
        end

        assert_equal :succeeded, result.state.to_sym
        new_repo = result.repository
        assert SecretScanning::Features::Repo::TokenScanning.new(new_repo).enabled?
        assert SecretScanning::Features::Repo::PushProtection.new(new_repo).enabled?
      end
    end
  end

  def create_repository(params = {}, repo_class = Repository)
    repo_params = {
      name: "reponame",
      description: "an description",
      public: true,
      user: @user,
    }.merge(params)
    owner = repo_params.delete(:owner)
    billing = repo_params.delete(:billing)
    user = repo_params.delete(:user)

    repo_class.handle_creation(
      user,
      owner,
      repo_params,
      reflog_data = {},
      billing,
    )
  end

  def fork_repository(repo:, dest_owner:, forker: nil)
    forker = dest_owner if forker.nil?

    orchestration = RepositoryOrchestration.fork(
      parent_repository: repo,
      actor: forker,
      owner: dest_owner,
    )

    refute_predicate orchestration.errors, :any?
    assert orchestration.valid?

    orchestration.execute

    orchestration.reload
  end

  # This heredoc is really messing with code syntax hightlighting and folding
  # Gonna just move it down here...
  def create_repo_graphql_mutation
    <<-'GRAPHQL'
      mutation($input: CreateRepositoryInput!) {
        createRepository(input: $input) {
          repository {
            name
            owner {
              login
            }
            isPrivate
            description
            isTemplate
            homepageUrl
            hasWikiEnabled
            hasIssuesEnabled
            defaultBranch
          }
        }
      }
    GRAPHQL
  end
end
