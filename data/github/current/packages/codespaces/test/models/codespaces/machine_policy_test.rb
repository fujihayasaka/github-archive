# typed: true
# frozen_string_literal: true

require "test_helper"

class MachinePolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  SkuMock = Struct.new(:name)

  fixtures do
    @user = create(:user)

    @user_repo = create(:repository, owner: @user, from_example: :simple)
    @random_private_repo = create(:private_repository)

    @business = create(:business)
    @org = create(:codespaces_organization, business: @business, plan: GitHub::Plan.business, admin: @user)
    @org.add_member(@user)
    @business.allow_private_repository_forking(force: true, actor: @user, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @user_repo_codespace = create(:codespace, owner: @user, repository: @user_repo, sku_name: :prototypePremiumLinux)
    @user_org_repo_codespace = create(:codespace, owner: @user, repository: @org_repo, sku_name: :extremeLinux)
    @org_dev_codespace = create(:codespace, owner: @user, vscs_target: :development, repository: @org_repo, sku_name: :premiumLinux)
    @policy_group = create(:policy_group, :all_targets, owner: @org)
  end

  context "filter_skus_by_machine_policy" do
    test "does no filtering if billable owner is a user" do
      skus = [SkuMock.new(name: :premiumLinux)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @user
      )
      assert_equal skus, result
    end

    test "does no filtering if billable owner nil" do
      skus = [SkuMock.new(name: :premiumLinux)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: nil
      )
      assert_equal skus, result
    end

    test "does no filtering if no constraints" do
      skus = [SkuMock.new(name: :premiumLinux)]
      Codespaces::MachinePolicy.stubs(:policy_constraints_for_user_and_repository).returns([])

      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal skus, result
    end

    test "filters by constraint allowlist (org only)" do
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :foobar), SkuMock.new(name: :baz)]

      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux], result.collect(&:name)
    end

    test "filters by intersection of constraints (org-wide and selected repo)" do
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      repo_targeted_policy_group = create(:policy_group, :selected_targets, owner: @org, name: "Foo", targets: [@org_repo])
      create(:policy_constraint, policy_group: repo_targeted_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux], result.collect(&:name)
    end

    test "filters by intersection of constraints (selected org and org-wide)" do
      enable_feature_flag(:codespaces_enterprise_policies)
      enable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :selected_targets, owner: @org.business, name: "Foo", targets: [@org])
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux], result.collect(&:name)
    end

    test "filters by intersection of constraints (enterprise-wide and org-wide)" do
      enable_feature_flag(:codespaces_enterprise_policies)
      enable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :all_targets, owner: @org.business, name: "Foo")
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux], result.collect(&:name)
    end

    test "ignores enterprise-owned, org-targeted policy without FF" do
      disable_feature_flag(:codespaces_enterprise_policies)
      enable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :selected_targets, owner: @org.business, name: "Foo", targets: [@org])
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux, :standardLinux32gb], result.collect(&:name).sort
    end

    test "ignores enterprise-wide policy without FF" do
      disable_feature_flag(:codespaces_enterprise_policies)
      enable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :all_targets, owner: @org.business, name: "Foo")
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux, :standardLinux32gb], result.collect(&:name).sort
    end

    test "ignores enterprise-owned, org-targeted policy without salus FF" do
      enable_feature_flag(:codespaces_enterprise_policies)
      disable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :selected_targets, owner: @org.business, name: "Foo", targets: [@org])
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux, :standardLinux32gb], result.collect(&:name).sort
    end

    test "ignores enterprise-wide policy without salus FF" do
      enable_feature_flag(:codespaces_enterprise_policies)
      disable_feature_flag(:codespaces_salus_beta_customers)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:standardLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      biz_policy_group = create(:policy_group, :all_targets, owner: @org.business, name: "Foo")
      create(:policy_constraint, policy_group: biz_policy_group, allowed_values: [:basicLinux32gb, :premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      skus = [SkuMock.new(name: :premiumLinux), SkuMock.new(name: :basicLinux32gb), SkuMock.new(name: :standardLinux32gb)]
      result = Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: skus,
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [:premiumLinux, :standardLinux32gb], result.collect(&:name).sort
    end

    test "returns empty list if skus arg is an empty list" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      assert_equal [], Codespaces::MachinePolicy.filter_skus_by_machine_policy(
        skus: [],
        repository: repo,
        billable_owner: org
      )
    end
  end

  context "machine_type_allowed?" do
    test "allows machine type without a machine policy constraint" do
      assert Codespaces::MachinePolicy.machine_type_allowed?(
        sku_name: @user_org_repo_codespace.sku_name,
        billable_owner: @user_org_repo_codespace.billable_owner,
        repository: @user_org_repo_codespace.repository
      ), "Expected machine type to be allowed"
    end

    test "allows machine type with a codespace allowed by org machine policy" do
      policy_constraint = @policy_group.policy_constraints.create!(name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES, allowed_values: ["basicLinux32gb"])
      codespace = create(:codespace, owner: @user, repository: @org_repo, sku_name: "basicLinux32gb")

      assert Codespaces::MachinePolicy.machine_type_allowed?(
        sku_name: codespace.sku_name,
        billable_owner: codespace.billable_owner,
        repository: codespace.repository
      ), "Expected machine type to be allowed"
    end

    test "disallows machine type with a codespace violating an org machine policy (org repo)" do
      policy_constraint = @policy_group.policy_constraints.create!(name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES, allowed_values: [])
      codespace = create(:codespace, owner: @user, repository: @org_repo, sku_name: "basicLinux")

      refute Codespaces::MachinePolicy.machine_type_allowed?(
        sku_name: codespace.sku_name,
        billable_owner: codespace.billable_owner,
        repository: codespace.repository
      ), "Expected machine type to be disallowed"
    end

    test "disallows machine type with a codespace violating an org machine policy (fork of org repo)" do
      @org.allow_private_repository_forking(actor: @user)
      fork_repo = create(:fork_repository, forker: @user, fork_repo: @org_repo)
      policy_constraint = @policy_group.policy_constraints.create!(name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES, allowed_values: [])
      codespace = create(:codespace, owner: @user, repository: fork_repo, sku_name: "basicLinux")

      assert_equal codespace.billable_owner, @org
      refute Codespaces::MachinePolicy.machine_type_allowed?(
        sku_name: codespace.sku_name,
        billable_owner: codespace.billable_owner,
        repository: codespace.repository
      ), "Expected machine type to be disallowed"
    end

    test "allows machine type for a user-billed codespace" do
      organization = create(:organization)
      org_owned_repo = create(:repository, owner: organization)
      codespace = create(:codespace, owner: @user, billable_owner: @user, repository: org_owned_repo, enable_org_access: false, sku_name: "basicLinux")
      policy_group = create(:policy_group, :all_targets, name: "Test Policy Group", owner: organization)
      policy_constraint = policy_group.policy_constraints.create!(name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES, allowed_values: [])

      assert Codespaces::MachinePolicy.machine_type_allowed?(
        sku_name: codespace.sku_name,
        billable_owner: codespace.billable_owner,
        repository: codespace.repository
      ), "Expected machine type to be allowed"
    end
  end
end unless GitHub.enterprise?
