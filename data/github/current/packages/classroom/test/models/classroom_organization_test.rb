# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomOrganizationTest < GitHub::TestCase
  test "wraps github organization" do
    github_organization = create :organization
    classroom_organization = ClassroomOrganization.locate(organization_id: github_organization.id)

    assert_equal github_organization.login, classroom_organization.login
  end

  test "surfaces plan display name" do
    github_organization = create :business_organization
    classroom_organization = ClassroomOrganization.new(github_organization)
    assert_equal "team", classroom_organization.plan
  end

  context "#meets_minimal_plan_for_classroom_codespaces?" do
    test "returns true if on teams plan" do
      github_organization = create :business_organization
      classroom_organization = ClassroomOrganization.new(github_organization)
      assert classroom_organization.meets_minimal_plan_for_classroom_codespaces?
    end

    test "returns true if on enterprise plan" do
      github_organization = create :business_plus_organization
      classroom_organization = ClassroomOrganization.new(github_organization)
      assert classroom_organization.meets_minimal_plan_for_classroom_codespaces?
    end

    test "returns false for free plan" do
      github_organization = create :free_organization
      classroom_organization = ClassroomOrganization.new(github_organization)
      refute classroom_organization.meets_minimal_plan_for_classroom_codespaces?
    end
  end

  context "#classroom_codespaces_setup_status" do
    test "returns status for each step" do
      github_organization = create :organization
      GitHub.flipper[:codespaces_billing_free].disable(github_organization)
      classroom_organization = ClassroomOrganization.new(github_organization)
      expected = { codespaces_allowed: false, codespaces_billing_free: false, codespaces_limit: "all_users_and_outside_collaborators" }
      assert_equal expected, classroom_organization.classroom_codespaces_setup_status
    end
  end

  context "#enable_classroom_codespaces", skip_enterprise: true do
    test "flips flags and changes limit to make codespaces free" do
      github_organization = create :business_organization
      classroom_organization = ClassroomOrganization.new(github_organization)
      classroom_organization.enable_classroom_codespaces(create(:classroom_user))
      expected = { codespaces_allowed: true, codespaces_billing_free: true, codespaces_limit: "all_users_and_outside_collaborators" }
      assert_equal expected, classroom_organization.classroom_codespaces_setup_status
    end
  end

  context "#disable_classroom_codespaces", skip_enterprise: true do
    test "removes flag and sets limit to disabled" do
      github_organization = create :business_organization
      github_organization = create(:enterprise_linked_organization)
      teacher = create(:classroom_user)
      classroom_organization = ClassroomOrganization.new(github_organization)
      classroom_organization.enable_classroom_codespaces(teacher)
      classroom_organization.disable_classroom_codespaces(teacher)
      expected = { codespaces_allowed: true, codespaces_billing_free: false, codespaces_limit: "all_users_and_outside_collaborators" }
      assert_equal expected, classroom_organization.classroom_codespaces_setup_status
    end
  end

  context "#classroom_codespaces_enabled?", skip_enterprise: true do
    test "returns if it's been enabled" do
      github_organization = create :business_organization
      GitHub.flipper[:codespaces_billing_free].disable(github_organization)
      classroom_organization = ClassroomOrganization.new(github_organization)

      refute classroom_organization.classroom_codespaces_enabled?

      classroom_organization.enable_classroom_codespaces(create(:classroom_user))

      assert classroom_organization.classroom_codespaces_enabled?
    end
  end

  context "#set_codespaces_policy" do
    test "sets to a basic machine" do
      github_organization = create :business_organization
      classroom_organization = ClassroomOrganization.new(github_organization)
      classroom_organization.set_codespaces_policy(actor: create(:user))
      policy_group = github_organization.policy_groups.find_by(name: "Education Codespaces Benefit Policy")

      assert_equal 1, policy_group.policy_constraints.count
      assert_equal "codespaces.allowed_machine_types", policy_group.policy_constraints.first.name
      assert_equal ["basicLinux32gb"], policy_group.policy_constraints.first.allowed_values
    end

    test "noops if already set" do
      github_organization = create :business_organization
      user = create(:user)
      classroom_organization = ClassroomOrganization.new(github_organization)
      classroom_organization.set_codespaces_policy(actor: user)
      classroom_organization.set_codespaces_policy(actor: user)

      assert_equal 1, github_organization.policy_groups.find_by(name: "Education Codespaces Benefit Policy").policy_constraints.count
    end
  end

  context "#remove_codespaces_policy" do
    test "removes the policy if it exists" do
      github_organization = create :business_organization
      user = create(:user)
      classroom_organization = ClassroomOrganization.new(github_organization)
      classroom_organization.set_codespaces_policy(actor: user)

      classroom_organization.remove_codespaces_policy(actor: user)
      refute github_organization.policy_groups.exists?(name: "Education Codespaces Benefit Policy")
    end

    test "noops if it doesn't exist" do
      github_organization = create :business_organization
      user = create(:user)
      classroom_organization = ClassroomOrganization.new(github_organization)

      classroom_organization.remove_codespaces_policy(actor: user)
      refute github_organization.policy_groups.exists?(name: "Education Codespaces Benefit Policy")
    end
  end
end
