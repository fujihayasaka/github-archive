# typed: true
# frozen_string_literal: true

require "test_helper"
require "network_bundle/network_configuration_client"

class NetworkConfigurationTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @enterprise = create(:business)
    GitHub.flipper[:codespaces_vnet_injection_beta].enable(@enterprise)
    GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
    @user = create(:user)
    @enterprise_org = create(:codespaces_organization, admin: @user)
    @enterprise.add_organization(@enterprise_org)
    @enterprise_repo = create(:private_repository, owner: @enterprise_org)
    @org = create(:codespaces_organization, admin: @user)
    @repo = create(:private_repository, owner: @org)
    @policy_group_org = create(:policy_group, owner: @enterprise_org, name: "all repos")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @enterprise_org)
    @policy_group_repo = create(:policy_group, owner: @enterprise_org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @enterprise_repo)
    @network_config_id = "12334567890"
    @network_config_name = "Some Network Name"
    @params = {
      id: @network_config_id,
      name: @network_config_name,
    }
  end

  context ".for" do
    test "returns nil if org isn't part of enterprise" do
      assert_nil Codespaces::NetworkConfiguration.for(repository: @repo, billable_owner: @org, actor: @user)
    end

    test "returns nil if enterprise isn't flagged in to vnet injection beta" do
      GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
      GitHub.flipper[:codespaces_vnet_injection_beta].disable(@enterprise)
      assert_nil Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
    end

    test "returns nil if enterprise isn't flagged in to salus beta" do
      GitHub.flipper[:codespaces_salus_beta_customers].disable(@enterprise)
      GitHub.flipper[:codespaces_vnet_injection_beta].enable(@enterprise)
      assert_nil Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
    end

    test "returns nil if no network configuration org policy is set" do
      assert_nil Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
    end

    test "returns network configuration if set at org level" do
      create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      result = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil result
      assert_equal @network_config_id, T::must(result).id
      assert_equal @network_config_name, T::must(result).name
    end

    test "returns network configuration if set at repo level" do
      create(:policy_constraint, policy_group: @policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      result = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil result
      assert_equal @network_config_id, T::must(result).id
      assert_equal @network_config_name, T::must(result).name
    end
  end

  context ".list_for_billable_owner" do
    test "returns empty array if org isn't part of enterprise" do
      assert_equal [], Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: @org)
    end

    test "returns empty array if enterprise isn't flagged into vnet injection beta" do
      GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
      GitHub.flipper[:codespaces_vnet_injection_beta].disable(@enterprise)
      assert_equal [], Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: @enterprise_org)
    end

    test "returns empty array if enterprise isn't flagged into salus beta" do
      GitHub.flipper[:codespaces_salus_beta_customers].disable(@enterprise)
      GitHub.flipper[:codespaces_vnet_injection_beta].enable(@enterprise)
      assert_equal [], Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: @enterprise_org)
    end

    test "returns empty array if network service doesn't have any network configurations for enterprise" do
      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:list).with(@enterprise, "codespaces", "", true).returns([])
      assert_equal [], Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: @enterprise_org)
    end

    test "returns network configurations for enterprise" do
      mock_config_name = "some config name"
      mock_config_id = "some-config-id"
      mock_config = NetworkBundle::NetworkConfiguration.new.tap do |config|
        config.name = mock_config_name
        config.id = mock_config_id
      end
      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:list_configurations).with(@enterprise, "codespaces", "", true).returns([mock_config])
      configs = Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: @enterprise_org)
      refute_nil configs
      config = T::must(T::must(configs).first)
      assert_equal mock_config_name, config.name
      assert_equal mock_config_id, config.id
    end
  end

  context "#regions" do
    test "returns empty array if network configuration has no network settings" do
      mock_config_id = "some-config-id"
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: [],
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_equal [], T::must(config).regions
    end

    test "returns region if set in network settings on network configuration" do
      mock_config_id = "some-config-id"
      mock_config_region = "EastUs"
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: [
            NetworkBundle::ComputeResourceNetworkResource.new(
              id: "some-settings-id",
              name: "some settings name",
              state: "active",
              location: mock_config_region,
              subnet_id: "/some/subnet/id",
            )
          ],
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_equal [mock_config_region], T::must(config).regions
    end

    test "returns multiple regions if configuration has multiple settings with different regions" do
      mock_config_id = "some-config-id"
      mock_config_regions = %w(EastUs EastUs2)
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: mock_config_regions.map do |region|
            NetworkBundle::ComputeResourceNetworkResource.new(
              id: "some-settings-id",
              name: "some settings name",
              state: "active",
              location: region,
              subnet_id: "/some/subnet/id",
            )
          end,
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_equal mock_config_regions.sort, T::must(config).regions.sort
    end
  end

  context "#subnet_id" do
    test "returns subnet ID for region" do
      mock_config_id = "some-config-id"
      mock_config_region = "EastUs"
      mock_config_subnet_id = "/some/subnet/id"
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: [
            NetworkBundle::ComputeResourceNetworkResource.new(
              id: "some-settings-id",
              name: "some settings name",
              state: "active",
              location: mock_config_region,
              subnet_id: mock_config_subnet_id,
            )
          ],
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_equal mock_config_subnet_id, T::must(config).subnet_id(mock_config_region)
    end

    test "raises NotFoundForRegion if requested region isn't in network configuration" do
      mock_config_id = "some-config-id"
      mock_config_region = "EastUs"
      mock_config_subnet_id = "/some/subnet/id"
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: [
            NetworkBundle::ComputeResourceNetworkResource.new(
              id: "some-settings-id",
              name: "some settings name",
              state: "active",
              location: mock_config_region,
              subnet_id: mock_config_subnet_id,
            )
          ],
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_raises(Codespaces::NetworkConfiguration::NotFoundForRegion) do
        T::must(config).subnet_id("WestUs")
      end
    end

    test "raises NotFoundForRegion if network configuration has no network settings" do
      mock_config_id = "some-config-id"
      mock_config = NetworkBundle::ComputeResourceConfiguration.new(
        id: mock_config_id,
        service: "codespaces",
        network_configuration: NetworkBundle::ComputeResourceNetworkConfiguration.new(
          id: mock_config_id,
          enabled: true,
          network_resources: [],
        ),
      )

      NetworkBundle::NetworkConfigurationClient.any_instance.stubs(:get_compute_resources).with(@enterprise, "codespaces", mock_config_id).returns(mock_config)
      params = {
        id: mock_config_id,
        name: "some config name",
      }
      create(:policy_constraint, policy_group: @policy_group_org, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      config = Codespaces::NetworkConfiguration.for(repository: @enterprise_repo, billable_owner: @enterprise_org, actor: @user)
      refute_nil config
      assert_raises(Codespaces::NetworkConfiguration::NotFoundForRegion) do
        T::must(config).subnet_id("EastUs")
      end
    end
  end
end
