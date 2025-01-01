# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesAccessCheckerTest < GitHub::TestCase
  include ::Billing::CodespacesUsageHelpers
  include CodespacesRepoHelper
  include DogstatsTestHelpers

  fixtures do
    GitHub.flipper[:codespaces_offboarding_force_limit].disable
    GitHub.flipper[:codespaces_billing_free].disable
    @user = create(:credit_card_user, plan: GitHub::Plan.pro)
    @non_org_user = create(:credit_card_user, plan: GitHub::Plan.pro)
    @org = create(:credit_card_organization, plan: GitHub::Plan.business)
    @org.add_member(@user)
    @repository = create(:repository, owner: @org)
    @enterprise_linked_org = create(:enterprise_linked_org)
  end
  [true, false].each do |v_next_enabled|
    context "#allowed? with vnext #{v_next_enabled}" do
      test "pulls data from cache when available" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)

        checker = Codespaces::AccessChecker.new(@org, repository: @repository)
        checker.expects(:get_cached_allowed_reason).twice.returns(:disallowed_by_payment_method)
        checker.billing_access_checker.expects(:perform).never
        checker.allowed?
        checker.allowed?
      end

      test "returns false when billing isn't allowed" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)
        checker = Codespaces::AccessChecker.new(@org, repository: @repository)
        checker.billing_access_checker.expects(:perform).returns(Codespaces::Access::AllowedResult.new(:disallowed_by_payment_method))
        refute checker.allowed?
      end

      test "returns false when billing isn't allowed for CW codespaces" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)
        checker = Codespaces::AccessChecker.new(@org, user: @user, repository: @repository, copilot_workspace: true)
        checker.billing_access_checker.expects(:perform).returns(Codespaces::Access::AllowedResult.new(:disallowed_by_payment_method))
        refute checker.allowed?
      end

      test "returns true when billing is allowed and billable owner is a user" do
        @user.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)
        repository = create(:repository, owner: @user)
        checker = Codespaces::AccessChecker.new(@user, repository: repository)
        checker.billing_access_checker.expects(:perform).returns(Codespaces::Access::AllowedResult.new(:allowed))
        assert checker.allowed?
      end

      test "returns false when policies aren't allowed" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)

        checker = Codespaces::AccessChecker.new(@org, repository: @repository)
        checker.billing_access_checker.expects(:perform).returns(Codespaces::Access::AllowedResult.new(:allowed))
        checker.expects(:calculate_allowed_by_policy).returns(Codespaces::Access::AllowedResult.new(:disallow_machine_policy))
        refute checker.allowed?
      end

      test "returns true when policies and billing are allowed" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: v_next_enabled)
        checker = Codespaces::AccessChecker.new(@org, repository: @repository)
        checker.billing_access_checker.expects(:perform).returns(Codespaces::Access::AllowedResult.new(:allowed))
        checker.expects(:calculate_allowed_by_policy).returns(Codespaces::Access::AllowedResult.new(:allowed))
        assert checker.allowed?
      end
    end
  end

  context "#calculate_allowed_by_policy" do
    test "checks machine type policies" do
      # Creates a policy where *no* machine types are allowed
      policy_group = create(:policy_group, :all_targets, owner: @org)
      create(:policy_constraint, policy_group:, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES, allowed_values: [])

      sku_name = "basicLinux32gb"
      repository = create(:repository, owner: @org)
      checker = Codespaces::AccessChecker.new(@org, repository: repository)

      usage_result = checker.send(:calculate_allowed_by_policy, sku_name:, dev_container: nil)
      assert usage_result.disallowed_by_machine_policy?
    end

    test "checks image policies" do
      # Creates a policy where *no* machine types are allowed
      policy_group = create(:policy_group, :all_targets, owner: @org)
      create(:policy_constraint, policy_group:, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES, allowed_values: ["foo/*"])

      repository = repo_with_devcontainer "{ image: \"bar/image\" }", repo_owner: @org
      oid = repository.refs.find("master").target_oid
      dev_container = Codespaces::DevContainer.new(repository:, oid:)
      checker = Codespaces::AccessChecker.new(@org, repository: repository)

      usage_result = checker.send(:calculate_allowed_by_policy, dev_container:, sku_name: nil)
      assert usage_result.disallowed_by_image_policy?
    end
  end

  context "#prebuild_allowed?" do
    test "returns true when usage is available", skip_enterprise: true do
      checker = Codespaces::AccessChecker.new(@org)
      checker.billing_access_checker.expects(:perform).with(prebuild: true).returns(Codespaces::Access::AllowedResult.new(:allowed))
      assert checker.prebuild_allowed?
    end

    test "returns false when usage is disallowed", skip_enterprise: true do
      checker = Codespaces::AccessChecker.new(@org)
      checker.billing_access_checker.expects(:perform).with(prebuild: true).returns(Codespaces::Access::AllowedResult.new(:disallow_payment_method))
      refute checker.prebuild_allowed?
    end
  end

  context "#billing_access_checker" do
    test "returns v next billing checker when v next enabled" do
      @org.billing_customer.create_billing_platform_enabled_product(codespaces: true)
      checker = Codespaces::AccessChecker.new(@org)
      assert_equal Codespaces::Access::VNextBillingChecker, checker.billing_access_checker.class
    end

    test "returns meuse billing checker when v next disabled" do
      @org.billing_customer.create_billing_platform_enabled_product(codespaces: false)
      checker = Codespaces::AccessChecker.new(@org)
      assert_equal Codespaces::Access::MeuseBillingChecker, checker.billing_access_checker.class
    end

    test "returns copilot workspace billing checker when requested" do
      checker = Codespaces::AccessChecker.new(@user, user: @user, copilot_workspace: true)
      assert_equal Codespaces::Access::CopilotWorkspaceBillingChecker, checker.billing_access_checker.class
    end

    test "raise an exception when asked to check copilot workspace usage with only a billable owner provided" do
      assert_raises_with_message ArgumentError, "a user must be provided in order to check usage for Copilot Workspaces" do
        Codespaces::AccessChecker.new(@user, user: nil, copilot_workspace: true)
      end
    end

    test "returns workspace editor billing checker when requested if flag is enabled" do
      checker = Codespaces::AccessChecker.new(@user, user: @user, workspace_editor_cloudspace: true)
      assert_equal Codespaces::Access::WorkspaceEditorBillingChecker, checker.billing_access_checker.class
    end

    test "caches the result when v next enabled" do
      @org.billing_customer.create_billing_platform_enabled_product

      @org.billing_customer.billing_platform_enabled_product.expects(:codespaces?).once.returns(true)
      Codespaces::AccessChecker.new(@org).billing_access_checker
      Codespaces::AccessChecker.new(@org).billing_access_checker
    end

    test "caches the result when v next disabled" do
      @org.billing_customer.create_billing_platform_enabled_product

      @org.billing_customer.billing_platform_enabled_product.expects(:codespaces?).once.returns(false)
      Codespaces::AccessChecker.new(@org).billing_access_checker
      Codespaces::AccessChecker.new(@org).billing_access_checker
    end
  end

  context ".from_codespace" do
    test "uses fast timeout by default" do
      codespace = create(:codespace)
      checker = Codespaces::AccessChecker.from_codespace(codespace)
      assert checker.fast_timeout
    end

    test "uses workspace editor cloudspace when codespace is a workspace editor cloudspace" do
      codespace = create(:workspace_editor_cloud_environment)
      checker = Codespaces::AccessChecker.from_codespace(codespace)
      assert_equal Codespaces::Access::WorkspaceEditorBillingChecker, checker.billing_access_checker.class
    end
  end
end
