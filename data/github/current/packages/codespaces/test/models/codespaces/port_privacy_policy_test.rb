# typed: true
# frozen_string_literal: true

require "test_helper"

class PortPrivacyPolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)

    @user_repo = create(:repository, owner: @user)

    @org = create(:codespaces_organization, admin: @user)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group = create(:policy_group, owner: @org)
    create(:policy_group_membership, policy_group: @policy_group, target: @org)
  end

  context "get_allowed_port_privacy_settings" do
    test "returns private and public if billable owner is a user" do
      port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]
      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: @org_repo,
        billable_owner: @user
      )
      assert_equal port_privacy_settings, result
    end

    test "returns private, org and public if no constraints and org billable owner" do
      port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal port_privacy_settings, result
    end

    test "returns private and public if no billable_owner" do
      port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: @org_repo,
        billable_owner: nil
      )
      assert_equal port_privacy_settings, result
    end

    test "returns private, org and public if no repo" do
      port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: nil,
        billable_owner: @org
      )
      assert_equal port_privacy_settings, result
    end

    test "gets intersection of constraints" do
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE]], result
    end

    test "returns private if no port privacy settings are allowed (org repo)" do
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: @org_repo,
        billable_owner: @org
      )
      assert_equal [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE]], result
    end

    test "returns private if no port privacy settings are allowed (fork of org repo)" do
      @org.allow_private_repository_forking(actor: @user)
      fork_repo = create(:fork_repository, forker: @user, fork_repo: @org_repo)
      create(:policy_constraint, policy_group: @policy_group, allowed_values: [], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)

      result = Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(
        repository: fork_repo,
        billable_owner: @org
      )
      assert_equal [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE]], result
    end
  end
end unless GitHub.enterprise?
