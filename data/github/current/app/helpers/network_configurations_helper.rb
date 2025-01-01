# typed: true
# frozen_string_literal: true

module NetworkConfigurationsHelper
  require "network_bundle/network_configuration_client"
  include NetworkBundle

  private

  sig { params(actor: T.any(Business, Organization)).returns(T::Array[String]) }
  def list_disabled_network_configuration_ids(actor)
    return [] if GitHub.enterprise?
    begin
      # list all network configurations that are disabled
      network_config_client
        .list_configurations(actor, "actions", "", false, "")
        .flat_map { |config| config.runner_groups }
        .map { |group| group["id"].to_s }
    rescue  NetworkBundle::NetworkConfigurationsException => e
      []
    end
  end

  sig { params(actor: T.any(Business, Organization)).returns(T::Boolean) }
  def can_view_network_configuration?(actor)
    return false if GitHub.enterprise?
    actor.is_a?(Business) || can_org_view_network_configuration?(actor) || can_edit_network_configuration?(actor)
  end

  sig { params(actor: Organization).returns(T::Boolean) }
  def can_org_view_network_configuration?(actor)
    return false if GitHub.enterprise?

    # The org is in an enterprise, it can always view the configuration
    return true if actor.delegate_billing_to_business?

    # Orgs on Team and Enterprise plans can always view the configurations
    plan_allows_network_configurations?(actor)
  end

  sig { params(actor: T.any(Business, Organization)).returns(T::Boolean) }
  def can_edit_network_configuration?(actor)
    return false if GitHub.enterprise?
    actor.is_a?(Business) || can_org_edit_network_configuration?(actor)
  end

  sig { params(actor: Organization).returns(T::Boolean) }
  def can_org_edit_network_configuration?(actor)
    return false if GitHub.enterprise?

    if actor.delegate_billing_to_business?
      # The org is in an enterprise, check that the business allows it to edit configs
      return actor.business&.network_configuration_creation_by_org_enabled? == true
    end

    plan_allows_network_configurations?(actor)
  end

  sig { params(actor: T.any(Business, Organization)).returns(T::Boolean) }
  def plan_allows_network_configurations?(actor)
    return false if GitHub.enterprise?
    return true if actor.is_a?(Business)
    # Team and Enterprise plan orgs are allowed
    actor.plan.business? || actor.plan.business_plus?
  end

  # Returns a phrase that explains why can_edit_network_configuration returned false
  sig { params(actor: T.any(Business, Organization)).returns(T.nilable(String)) }
  def edit_prevention_reason(actor)
    # See can_org_edit_network_configuration for matching logic
    return "GitHub Enterprise Server is not a supported environment" if GitHub.enterprise?
    if actor.is_a?(Business)
      return nil
    end
    return "Network configuration management is disabled at the enterprise" if actor.delegate_billing_to_business? && actor.business&.network_configuration_creation_by_org_enabled? == false
    return "Team or Enterprise plan is required" if !plan_allows_network_configurations?(actor)
    nil
  end

  sig { params(config: NetworkBundle::NetworkConfiguration).returns(T::Hash[String, T.untyped]) }
  def network_config_to_payload(config)
    # These keys must match the names in ui/packages/network-configurations/classes/network-configuration.ts
    {
      id: config.id,
      name: config.name,
      createdOn: config.created_on,
      computeService: config.compute_service,
      service: config.service,
      runnerGroups: config.runner_groups.map do |runner_group|
        {
          id: runner_group["id"],
          name: runner_group["name"],
          allowPublic: runner_group["allowPublic"],
          visibility: runner_group["visibility"],
          selectedTargetsCount: runner_group["selectedTargetsCount"],
        }
      end
    }
  end

  sig { params(settings: NetworkBundle::NetworkSettings).returns(T::Hash[String, T.untyped]) }
  def network_settings_to_payload(settings)
    # These keys must match the names in ui/packages/network-configurations/classes/private-network.class.ts
    {
      id: settings.id,
      subscription: settings.subscription,
      virtualNetwork: settings.virtual_network,
      location: settings.location,
      subnet: settings.subnet,
      resourceGroup: settings.resource_group,
      resourceName: settings.resource_name,
      networkConfigurationId: settings.network_configuration_id,
    }
  end

  sig { params(verbose: T::Boolean).returns(NetworkBundle::NetworkConfigurationClient) }
  def network_config_client(verbose: false)
    NetworkBundle::NetworkConfigurationClient.create(verbose: verbose)
  end
end
