# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPolicyGroupMembershipTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @policy_group = Codespaces::PolicyGroup.create!(
      owner: @org,
      owner_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_USER,
      name: "My Test Policies",
    )
  end

  context "validation" do
    test "disallows double membership" do
      Codespaces::PolicyGroupMembership.create!(
        policy_group: @policy_group,
        target_id: @org.id,
        target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_USER,
      )
      membership = Codespaces::PolicyGroupMembership.new(
        policy_group: @policy_group,
        target_id: @org.id,
        target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_USER,
      )

      refute membership.valid?
    end

    test "disallows an undeclared target_type" do
      refute_includes Codespaces::PolicyGroupMembership::TARGET_TYPES, "Organization"

      user = create(:user)
      membership = Codespaces::PolicyGroupMembership.new(
        policy_group: @policy_group,
        target_id: user.id,
        target_type: "Organization",
      )

      refute membership.valid?
      assert membership.errors[:target_type].any?, "expected 'Organization' to be an invalid target_type"
    end

    test "allows a Repository target_type" do
      repository = create(:repository, owner: @org)

      assert_nothing_raised do
        Codespaces::PolicyGroupMembership.create!(
          policy_group: @policy_group,
          target_id: repository.id,
          target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY,
        )
      end
    end

    test "disallows an individual User target" do
      user = create(:user)
      membership = Codespaces::PolicyGroupMembership.new(
        policy_group: @policy_group,
        target_id: user.id,
        target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_USER,
      )

      refute membership.valid?
      assert membership.errors["target"].any?, "expected individual User to be an invalid target"
    end
  end
end
