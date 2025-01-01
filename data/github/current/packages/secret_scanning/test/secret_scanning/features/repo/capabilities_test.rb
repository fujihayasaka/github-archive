# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class CapabilitiesTest < GitHub::TestCase
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @org = create(:business_plus_org, business: @business)
      @repo = create(:repository, owner: @org)
      @user = create(:user)

      @ghas_org = create(:business_plus_org, business: @business)
      @non_ghas_org = create(:business_plus_org, business: @business)
    end

    setup do
      GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      @ghas_org.stubs(:advanced_security_purchased?).returns(true)
      @non_ghas_org.stubs(:advanced_security_purchased?).returns(false)

      # ghas repos
      @private_ghas_repo = create(:private_repository, owner: @ghas_org)
      @private_ghas_repo.stubs(:advanced_security_enabled?).returns(true)
      refute @private_ghas_repo.public?
      refute @private_ghas_repo.archived?
      @private_ghas_repo_with_ghas_disabled = create(:private_repository, owner: @ghas_org)
      @private_ghas_repo_with_ghas_disabled.stubs(:advanced_security_enabled?).returns(false)
      refute @private_ghas_repo_with_ghas_disabled.public?
      refute @private_ghas_repo_with_ghas_disabled.archived?
      @public_ghas_repo = create(:public_repository, owner: @ghas_org)
      @public_ghas_repo.stubs(:advanced_security_enabled?).returns(true)
      assert @public_ghas_repo.public?
      refute @public_ghas_repo.archived?
      @archived_private_ghas_repo = create(:private_repository, owner: @ghas_org)
      @archived_private_ghas_repo.stubs(:archived?).returns(true)
      refute @archived_private_ghas_repo.public?
      assert @archived_private_ghas_repo.archived?
      @archived_public_ghas_repo = create(:public_repository, owner: @ghas_org)
      @archived_public_ghas_repo.stubs(:archived?).returns(true)
      assert @archived_public_ghas_repo.public?
      assert @archived_public_ghas_repo.archived?

      # # non ghas repos
      @private_non_ghas_repo = create(:private_repository, owner: @non_ghas_org)
      refute @private_non_ghas_repo.public?
      refute @private_non_ghas_repo.archived?
      @public_non_ghas_repo = create(:public_repository, owner: @non_ghas_org)
      assert @public_non_ghas_repo.public?
      refute @public_non_ghas_repo.archived?
      @archived_private_non_ghas_repo = create(:private_repository, owner: @non_ghas_org)
      @archived_private_non_ghas_repo.stubs(:archived?).returns(true)
      refute @archived_private_non_ghas_repo.public?
      assert @archived_private_non_ghas_repo.archived?
      @archived_public_non_ghas_repo = create(:public_repository, owner: @non_ghas_org)
      @archived_public_non_ghas_repo.stubs(:archived?).returns(true)
      assert @archived_public_non_ghas_repo.public?
      assert @archived_public_non_ghas_repo.archived?

      # user repos
      @private_user_repo = create(:private_repository, owner: @user)
      refute @private_user_repo.public?
      refute @private_user_repo.archived?
      @public_user_repo = create(:public_repository, owner: @user)
      assert @public_user_repo.public?
      refute @public_user_repo.archived?
      @archived_private_user_repo = create(:private_repository, owner: @user)
      @archived_private_user_repo.stubs(:archived?).returns(true)
      refute @archived_private_user_repo.public?
      assert @archived_private_user_repo.archived?
      @archived_public_user_repo = create(:public_repository, owner: @user)
      @archived_public_user_repo.stubs(:archived?).returns(true)
      assert @archived_public_user_repo.public?
      assert @archived_public_user_repo.archived?

      @capabilities = SecretScanning::Features::Repo::Capabilities.new(@repo)
    end


    class CapabilitiesTestCase < T::ImmutableStruct
      const :repo,                    Repository
      const :scannable,               T::Boolean, default: false
      const :results_visible,         T::Boolean, default: false
      const :ghas_secret_scanning,    T::Boolean, default: false
    end

    context "verify standard capabilities for various repository setups" do
      test "when secret scanning is enabled (dotcom)", skip_enterprise: true do


        # These test cases cover the standard expectations when Secret Scanning has been enabled by a user
        # ie. a private repo, in a GHAS org, with Secret Scanning enabled is expected to be scannable: true, results_visible: true, and ghas_secret_scanning: true
        # Note: free public repo experience is enabled for these tests
        test_cases = [
          # ghas org repos
          CapabilitiesTestCase.new(repo: @private_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @private_ghas_repo_with_ghas_disabled, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @archived_private_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @archived_public_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          # non ghas org repos
          CapabilitiesTestCase.new(repo: @private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_non_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_non_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: false),
          # user repos
          CapabilitiesTestCase.new(repo: @private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_user_repo, scannable: true, results_visible: true, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_user_repo, scannable: true, results_visible: true, ghas_secret_scanning: false),
        ]

        test_cases.each_with_index do |tc, i|
          SecretScanning::Features::Repo::TokenScanning.new(tc.repo).enable(actor: @user) # enable secret scanning

          capabilities = SecretScanning::Features::Repo::Capabilities.new(tc.repo)
          assert_equal tc.scannable, capabilities.scannable?, "scannable? failed for test case #{i}"
          assert_equal tc.results_visible, capabilities.results_visible?, "results_visible? failed for test case #{i}"
          assert_equal tc.ghas_secret_scanning, capabilities.ghas_secret_scanning?, "ghas_secret_scanning? failed for test case #{i}"
        end
      end

      test "when secret scanning is disabled (dotcom)", skip_enterprise: true do
        # These test cases cover the standard expectations when Secret Scanning has NOT been enabled by a user
        # ie. a private repo, in a GHAS org, with Secret Scanning DISABLED is expected to be scannable: false, results_visible: false, and ghas_secret_scanning: false
        # Note: free public repo experience is enabled for these tests
        test_cases = [
          # ghas org repos
          CapabilitiesTestCase.new(repo: @private_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @private_ghas_repo_with_ghas_disabled, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_ghas_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_ghas_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
          # non ghas org repos
          CapabilitiesTestCase.new(repo: @private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_non_ghas_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_non_ghas_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
          # user repos
          CapabilitiesTestCase.new(repo: @private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_user_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_user_repo, scannable: true, results_visible: false, ghas_secret_scanning: false),
        ]

        test_cases.each_with_index do |tc, i|
          SecretScanning::Features::Repo::TokenScanning.new(tc.repo).disable(actor: @user) # disable secret scanning

          capabilities = SecretScanning::Features::Repo::Capabilities.new(tc.repo)
          assert_equal tc.scannable, capabilities.scannable?, "scannable? failed for test case #{i}"
          assert_equal tc.results_visible, capabilities.results_visible?, "results_visible? failed for test case #{i}"
          assert_equal tc.ghas_secret_scanning, capabilities.ghas_secret_scanning?, "ghas_secret_scanning? failed for test case #{i}"
        end
      end

      test "when secret scanning is enabled (GHES)", enterprise_only: true do
        GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].disable
        # These test cases cover the standard expectations when Secret Scanning has been enabled by a user
        # ie. a private repo, in a GHAS org, with Secret Scanning enabled is expected to be scannable: true, results_visible: true, and ghas_secret_scanning: true
        # Note: in GHES there is no public scanning or free public repo experience so non-GHAS public repos should have no capabilities
        test_cases = [
          # ghas org repos
          CapabilitiesTestCase.new(repo: @private_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @private_ghas_repo_with_ghas_disabled, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @archived_private_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @archived_public_ghas_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          # non ghas org repos
          CapabilitiesTestCase.new(repo: @private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          # user repos
          CapabilitiesTestCase.new(repo: @private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_user_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
          CapabilitiesTestCase.new(repo: @archived_public_user_repo, scannable: true, results_visible: true, ghas_secret_scanning: true),
        ]

        test_cases.each_with_index do |tc, i|
          SecretScanning::Features::Repo::TokenScanning.new(tc.repo).enable(actor: @user) # enable secret scanning

          capabilities = SecretScanning::Features::Repo::Capabilities.new(tc.repo)
          assert_equal tc.scannable, capabilities.scannable?, "scannable? failed for test case #{i}"
          assert_equal tc.results_visible, capabilities.results_visible?, "results_visible? failed for test case #{i}"
          assert_equal tc.ghas_secret_scanning, capabilities.ghas_secret_scanning?, "ghas_secret_scanning? failed for test case #{i}"
        end
      end

      test "when secret scanning is disabled (GHES)", enterprise_only: true do
        GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].disable
        # These test cases cover the standard expectations when Secret Scanning has NOT been enabled by a user
        # ie. a private repo, in a GHAS org, with Secret Scanning DISABLED is expected to be scannable: false, results_visible: false, and ghas_secret_scanning: false
        # Note: in GHES there is no public scanning or free public repo experience so non-GHAS public repos should have no capabilities
        test_cases = [
          # ghas org repos
          CapabilitiesTestCase.new(repo: @private_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @private_ghas_repo_with_ghas_disabled, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          # non ghas org repos
          CapabilitiesTestCase.new(repo: @private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_non_ghas_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          # user repos
          CapabilitiesTestCase.new(repo: @private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @public_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_private_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
          CapabilitiesTestCase.new(repo: @archived_public_user_repo, scannable: false, results_visible: false, ghas_secret_scanning: false),
        ]

        test_cases.each_with_index do |tc, i|
          SecretScanning::Features::Repo::TokenScanning.new(tc.repo).disable(actor: @user) # disable secret scanning

          capabilities = SecretScanning::Features::Repo::Capabilities.new(tc.repo)
          assert_equal tc.scannable, capabilities.scannable?, "scannable? failed for test case #{i}"
          assert_equal tc.results_visible, capabilities.results_visible?, "results_visible? failed for test case #{i}"
          assert_equal tc.ghas_secret_scanning, capabilities.ghas_secret_scanning?, "ghas_secret_scanning? failed for test case #{i}"
        end
      end
    end

    context "repo is deleted" do
      test "false if repo is deleted" do
        # enable all the things that could possibly be enabled
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:enabled?).returns(true)

        Repository.any_instance.stubs(:deleted?).returns(true)

        refute @capabilities.scannable?
        refute @capabilities.results_visible?
        refute @capabilities.ghas_secret_scanning?
        refute @capabilities.validity_checks?
        refute @capabilities.lower_confidence_patterns?
        refute @capabilities.generic_secrets?
        refute @capabilities.wiki_scanning?
      end
    end

    context "to_hydro_msg" do
      test "gets unknown owner scope" do
        @repo.stubs(:owner).returns(nil)
        assert_equal :UNKNOWN_SCOPE, capabilities.to_hydro_msg[:owner_scope]
      end

      test "gets org owner scope" do
        assert_equal :ORGANIZATION_SCOPE, capabilities.to_hydro_msg[:owner_scope]
      end

      test "gets user owner scope" do
        capab = SecretScanning::Features::Repo::Capabilities.new(@public_user_repo)
        assert_equal :USER_SCOPE, capab.to_hydro_msg[:owner_scope]
      end
    end

    context "scannable?" do
      test "true if token scanning enabled and public scanning disabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        assert @capabilities.scannable?
      end

      test "true if token scanning disabled and public scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.scannable?
      end

      test "true if token and public scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.scannable?
      end

      test "false if token and public scanning disabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.scannable?
      end
    end

    context "results_visible?" do
      test "true if token scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.results_visible?
      end

      test "false if token scanning not enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.results_visible?
      end
    end

    context "ghas_secret_scanning?" do
      test "true if token scanning enabled and ghas repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        assert @capabilities.ghas_secret_scanning?
      end

      test "false if ghas repo but token scanning is not enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        refute @capabilities.ghas_secret_scanning?
      end

      test "false if token scanning is enabled but not a ghas repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute @capabilities.ghas_secret_scanning?
      end

      test "false if token scanning is not enabled and not a ghas repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        refute @capabilities.ghas_secret_scanning?
      end
    end

    context "validity_checks?" do
      test "returns true if the repo has validity checks enabled" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.validity_checks?
      end

      test "returns false if the repo does not have validity checks enabled" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.validity_checks?
      end
    end

    context "lower_confidence_patterns?" do
      test "returns true if the repo has lower confidence patterns enabled" do
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.lower_confidence_patterns?
      end

      test "returns false if the repo does not have lower confidence patterns enabled" do
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.lower_confidence_patterns?
      end
    end

    context "generic_secrets?" do
      test "returns true if the repo has generic secrets enabled" do
        SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.generic_secrets?
      end

      test "returns false if the repo does not have generic secrets enabled" do
        SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.generic_secrets?
      end
    end

    context "wiki_scanning?" do
      test "returns true if the repo has wiki scanning enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:enabled?).returns(true)
        assert @capabilities.wiki_scanning?
      end

      test "returns false if the repo does not have wiki scanning enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:enabled?).returns(false)
        refute @capabilities.wiki_scanning?
      end
    end

    private

    sig { returns(SecretScanning::Features::Repo::Capabilities) }
    def capabilities
      @capabilities
    end
  end
end
