# typed: true
# frozen_string_literal: true

require "test_helper"

class NetworkConfigurationPolicyTest < GitHub::TestCase
  fixtures do
    @enterprise = create(:business)
    GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
    GitHub.flipper[:codespaces_vnet_injection_beta].enable(@enterprise)
    @user = create(:user)
    @org = create(:codespaces_organization, admin: @user)
    @enterprise.add_organization(@org)

    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)

    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_org = create(:policy_group, owner: @org, name: "all repos")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @org)

    @policy_group_repo = create(:policy_group, owner: @org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @org_repo)

    @network_config_id = "12334567890"
    @network_config_name = "Some Network Name"
    @params = {
      id: @network_config_id,
      name: @network_config_name,
    }
  end

  context "#get_network_configuration" do
    test "gets network configuration if set at org level" do
      create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_equal @network_config_id, T.must(result)["id"]
      assert_equal @network_config_name, T.must(result)["name"]
    end

    test "gets network configuration if set at repo level" do
      create(:policy_constraint, policy_group: @policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_equal @network_config_id, T.must(result)["id"]
      assert_equal @network_config_name, T.must(result)["name"]
    end

    test "uses more specific policy if set at both org and repo level" do
      create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      other_network_config_id = "0987654321"
      other_network_config_name = "Other Network Name"
      other_params = {
        id: other_network_config_id,
        name: other_network_config_name,
      }
      create(:policy_constraint, policy_group: @policy_group_repo, params: other_params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_equal other_network_config_id, T.must(result)["id"]
      assert_equal other_network_config_name, T.must(result)["name"]
    end

    test "returns nil if FF is disabled" do
      GitHub.flipper[:codespaces_vnet_injection_beta].disable(@enterprise)
      create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_nil result
    end

    test "returns nil if policy doesn't exist" do
      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_nil result
    end

    test "returns nil if policy doesn't contain params" do
      create(:policy_constraint, policy_group: @policy_group_repo, allowed_values: [:premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @org,
      )

      assert_nil result
    end

    test "returns nil if org is not billable owner" do
      create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)

      result = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
        repository: @org_repo,
        billable_owner: @user,
      )

      assert_nil result
    end
  end
end
