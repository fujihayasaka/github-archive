# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/code_scanning/review_test_helpers"

module CodeScanning
  class AutofixCodeqlTest < GitHub::TestCase

    ResponseMock = Struct.new(:data)
    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @business = create(:global_business)
      @org = create(:organization)
      @user = create(:user)
      @private_repo = create(:private_repository, owner: @org, from_example: :simple)
      @public_repo = create(:public_repository, owner: @org, from_example: :simple)
    end

    setup do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      CodeScanning::Autofix.stubs(:available_in_environment?).returns(true)
      GitHub.flipper.disable(:code_scanning_suggested_all_queries)
    end

    context ".enabled_for_repo?" do
      test "returns false if settings are not configurable" do
        CodeScanning::AutofixCodeql.stubs(:repo_settings_configurable?).returns(false)
        CodeScanningRepositoryConfig.new(@private_repo).enable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.enabled_for_repo?(@private_repo)
      end

      test "returns true if settings are configurable and enabled (default)" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::AutofixCodeql.enabled_for_repo?(@private_repo)
      end

      test "returns false if settings are configurable but disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)
        CodeScanningRepositoryConfig.new(@private_repo).disable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.enabled_for_repo?(@private_repo)
      end
    end

    context ".repo_settings_configurable?" do
      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.repo_settings_configurable?(@private_repo)
      end

      test "returns true when the repo is public", skip_enterprise: true do
        public_repo = create(:public_repository, owner: @org)

        assert CodeScanning::AutofixCodeql.repo_settings_configurable?(public_repo)
      end

      test "returns false when advanced security is disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.disable_advanced_security(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.repo_settings_configurable?(@private_repo)
      end

      test "returns false for private repository when the owner is a user" do
        user_repo = create(:private_repository, owner: @user)

        refute CodeScanning::AutofixCodeql.repo_settings_configurable?(user_repo)
      end

      test "returns true for public repository when the owner is a user", skip_enterprise: true do
        user_public_repo = create(:public_repository, owner: @user)

        assert CodeScanning::AutofixCodeql.repo_settings_configurable?(user_public_repo)
      end

      test "returns true when autofix is enabled for the org" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::AutofixCodeql.repo_settings_configurable?(@private_repo)
      end

      test "returns false when autofix is disabled for the org" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)
        CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @org.admins.first)
        @private_repo.reload

        refute CodeScanning::AutofixCodeql.repo_settings_configurable?(@private_repo)
      end

      test "returns true when the repo is public and org has autofix enabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @public_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::AutofixCodeql.repo_settings_configurable?(@public_repo)
      end

      test "returns false when the repo is public and org has autofix disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @public_repo.enable_advanced_security(actor: @org.admins.first)
        CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @org.admins.first)
        @public_repo.reload

        refute CodeScanning::AutofixCodeql.repo_settings_configurable?(@public_repo)
      end
    end

    context ".enabled_for_org?" do
      test "returns false if settings are not configurable" do
        CodeScanning::AutofixCodeql.stubs(:org_settings_configurable?).returns(false)
        CodeScanningOrganizationConfig.new(organization: @org).enable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.enabled_for_org?(@org)
      end

      test "returns true if settings are configurable and enabled (default)" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)

        assert CodeScanning::AutofixCodeql.enabled_for_org?(@org)
      end

      test "returns false if settings are configurable but disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::AutofixCodeql.enabled_for_org?(@org)
      end
    end

    context ".org_settings_configurable?" do
      test "returns false if code scanning is not enabled" do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        GitHub.stubs(:code_scanning_enabled?).returns(false)

        refute CodeScanning::AutofixCodeql.org_settings_configurable?(@org)
      end

      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        refute CodeScanning::AutofixCodeql.org_settings_configurable?(@org)
      end

      test "returns true even if GHAS is not purchased" do
        @org.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

        assert CodeScanning::AutofixCodeql.org_settings_configurable?(@org)
      end

      test "returns true if GHAS purchased" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)

        assert CodeScanning::AutofixCodeql.org_settings_configurable?(@org)
      end

      test "respects enterprise autofix policy", skip_enterprise: true do
        business = create(:business)
        org = create(:organization, business:)
        repo = create(:private_repository, owner: org, from_example: :simple)
        business.mark_advanced_security_as_purchased_for_entity(actor: business.admins.first)

        assert CodeScanning::AutofixCodeql.org_settings_configurable?(org)

        business.disallow_code_scanning_autofix_policy(actor: business.admins.first)

        refute CodeScanning::AutofixCodeql.org_settings_configurable?(org)
      end

      test "returns true if the org is standalone" do
        standalone_org = create(:organization)

        assert CodeScanning::AutofixCodeql.org_settings_configurable?(standalone_org)
      end
    end

    context ".allowed_by_business?" do
      test "returns false if code scanning is not enabled" do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        GitHub.stubs(:code_scanning_enabled?).returns(false)

        refute CodeScanning::AutofixCodeql.allowed_by_business?(@business)
      end

      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        refute CodeScanning::AutofixCodeql.allowed_by_business?(@business)
      end

      test "returns false if GHAS is not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

        refute CodeScanning::AutofixCodeql.allowed_by_business?(@business)
      end

      test "returns true if GHAS purchased" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first) unless GitHub.enterprise?

        assert CodeScanning::AutofixCodeql.allowed_by_business?(@business)
      end

      test "returns false if disallowed", skip_enterprise: true do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first)
        @business.disallow_code_scanning_autofix_policy(actor: @business.admins.first)

        refute CodeScanning::AutofixCodeql.allowed_by_business?(@business)
      end
    end

    context ".policy_available?" do
      test "returns false if code scanning is not enabled" do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        GitHub.stubs(:code_scanning_enabled?).returns(false)

        refute CodeScanning::AutofixCodeql.policy_available?(@business)
      end

      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        refute CodeScanning::AutofixCodeql.policy_available?(@business)
      end

      test "returns false if GHAS is not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

        refute CodeScanning::AutofixCodeql.policy_available?(@business)
      end

      test "returns true if GHAS purchased" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first) unless GitHub.enterprise?

        assert CodeScanning::AutofixCodeql.policy_available?(@business)
      end
    end
  end
end
