# typed: true
# frozen_string_literal: true

require "test_helper"

class EntityPolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)

    @user_repo = create(:repository, owner: @user)
    @business = create(:business)
    @org = create(:codespaces_organization, admin: @user)
    @business.add_organization(@org)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_biz = create(:policy_group, owner: @business, name: "all orgs")
    @policy_group_org = create(:policy_group, owner: @org, name: "all repos")
    @policy_group_repo = create(:policy_group, owner: @org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_biz, target: @business)
    create(:policy_group_membership, policy_group: @policy_group_org, target: @org)
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @org_repo)

    @codespace_id = 1
  end

  context "#value" do
    context "business policy exists" do
      test "returns value of constraint" do
        create(:policy_constraint, policy_group: @policy_group_biz, allowed_values: ["all"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES)

        result = Codespaces::EntityPolicy.value(business: @business)

        assert_equal "all", result
      end

      test "returns the most restrictive value of constraint" do
        policy_group_biz2 = create(:policy_group, owner: @business, name: "selected orgs")
        create(:policy_group_membership, policy_group: policy_group_biz2, target: @business)

        create(:policy_constraint, policy_group: @policy_group_biz, allowed_values: ["all"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES)
        create(:policy_constraint, policy_group: policy_group_biz2, allowed_values: ["selected"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES)

        result = Codespaces::EntityPolicy.value(business: @business)

        assert_equal "selected", result
      end

      #TODO should be return something else?
      test "returns empty string if no business" do
        create(:policy_constraint, policy_group: @policy_group_biz, allowed_values: ["all"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES)

        result = Codespaces::EntityPolicy.value(business: nil)

        assert_equal "", result
      end

    end
    context "org policy does not exists" do
      test "defaults to all - codespaces will on by default" do
        result = Codespaces::EntityPolicy.value(business: @business)

        assert_equal "all", result
      end
    end
  end
end unless GitHub.enterprise?
