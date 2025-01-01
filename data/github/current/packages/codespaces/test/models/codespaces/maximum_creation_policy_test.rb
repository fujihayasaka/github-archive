# typed: true
# frozen_string_literal: true

require "test_helper"

class MaximumCreationPolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)

    @org = create(:codespaces_organization, admin: @user)
    @org.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_org = create(:policy_group, owner: @org, name: "all repos")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @org)

    @policy_group_org_2 = create(:policy_group, owner: @org, name: "all repos: 2")
    create(:policy_group_membership, policy_group: @policy_group_org_2, target: @org)
    @codespace_id = 1

    @enterprise_org_admin = create(:user)
    @enterprise = create(:business)
    @enterprise_org = create(:business_plus_organization, business: @enterprise, admin: @enterprise_org_admin)
    @enterprise.add_organization(@enterprise_org)

    @policy_group_enterprise = create(:policy_group, owner: @enterprise, name: "All orgs")
    create(:policy_group_membership, policy_group: @policy_group_enterprise, target: @enterprise)

    @policy_group_enterprise_2 = create(:policy_group, owner: @enterprise, name: "Some Orgs")
    create(:policy_group_membership, policy_group: @policy_group_enterprise_2, target: @enterprise_org)

    @policy_group_enterprise_org = create(:policy_group, owner: @enterprise_org, name: "Restrict my repos!")
    create(:policy_group_membership, policy_group: @policy_group_enterprise_org, target: @enterprise_org)
  end

  context "#get_applicable_creations_limit" do
    context "org policy" do
      context "org policy exists" do
        test "returns org creation limit policy" do
          create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@org)

          assert_equal 30, result
        end

        test "returns org creation limit policy when it is the lowest" do
          create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_org_2, maximum_value: 10, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@org)

          assert_equal 10, result
        end
      end

      context "org policy does not exist" do
        test "returns nil" do
          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@org)

          assert_nil result
        end
      end

      context "billable owner is a user" do
        test "returns nil" do
          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@user)

          assert_nil result
        end
      end

      context "targeted repo is not an org repo" do
        test "returns nil" do
          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@user)

          assert_nil result
        end
      end
    end

    context "enterprise policy" do
      context "enterprise policy exists" do
        test "returns enterprise creation limit policy" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@enterprise_org)

          assert_equal 20, result
        end

        test "returns enterprise creation limit policy when it is the lowest" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_2, maximum_value: 5, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@enterprise_org)

          assert_equal 5, result
        end
      end

      context "enterprise policy and org policy exist" do
        test "returns lowest policy when org has the lowest value" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_org, maximum_value: 5, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@enterprise_org)

          assert_equal 5, result
        end

        test "returns lowest policy when enterprise has the lowest value" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 10, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_org, maximum_value: 25, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@enterprise_org)

          assert_equal 10, result
        end
      end

      context "enterprise policy does not exist" do
        test "returns nil" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable
          result = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(@enterprise_org)

          assert_nil result
        end
      end
    end
  end

  context "#get_limit_and_policy_owner" do
    context "org policy" do
      context "org policy exists" do
        test "returns org creation limit policy" do
          create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@org)

          assert_equal [30, @org], result
        end

        test "returns org creation limit policy when it is the lowest" do
          create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_org_2, maximum_value: 10, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@org)

          assert_equal [10, @org], result
        end
      end

      context "org policy does not exist" do
        test "returns nil" do
          limit, policy_owner = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@org)

          assert_nil limit
          assert_nil policy_owner
        end
      end

      context "billable owner is a user" do
        test "returns nil" do
          limit, policy_owner = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@user)

          assert_nil limit
          assert_nil policy_owner
        end
      end

      context "targeted repo is not an org repo" do
        test "returns nil" do
          limit, policy_owner = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@user)

          assert_nil limit
          assert_nil policy_owner
        end
      end
    end

    context "enterprise policy" do
      context "enterprise policy exists" do
        test "returns enterprise creation limit policy" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@enterprise_org)

          assert_equal [20, @enterprise], result
        end

        test "returns enterprise creation limit policy when it is the lowest" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_2, maximum_value: 5, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@enterprise_org)

          assert_equal [5, @enterprise], result
        end
      end

      context "enterprise policy and org policy exist" do
        test "returns lowest policy when org has the lowest value" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 20, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_org, maximum_value: 5, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@enterprise_org)

          assert_equal [5, @enterprise_org], result
        end

        test "returns lowest policy when enterprise has the lowest value" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable

          create(:policy_constraint, policy_group: @policy_group_enterprise, maximum_value: 10, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
          create(:policy_constraint, policy_group: @policy_group_enterprise_org, maximum_value: 25, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

          result = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@enterprise_org)

          assert_equal [10, @enterprise], result
        end
      end

      context "enterprise policy does not exist" do
        test "returns nil" do
          GitHub.flipper[:codespaces_enterprise_policies].enable
          GitHub.flipper[:codespaces_salus_beta_customers].enable
          limit, policy_owner = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(@enterprise_org)

          assert_nil limit
          assert_nil policy_owner
        end
      end
    end
  end

end unless GitHub.enterprise?
