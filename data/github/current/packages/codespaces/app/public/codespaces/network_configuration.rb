# typed: strict
# frozen_string_literal: true

class Codespaces::NetworkConfiguration
  extend T::Sig
  require "network_bundle/network_configuration_client"

  NotFoundForRegion = Class.new(StandardError)

  sig { returns(T.nilable(String)) }
  attr_reader :id

  sig { returns(T.nilable(String)) }
  attr_reader :name

  sig do
    params(
      repository: Repository,
      billable_owner: User,
      actor: User,
    ).returns(T.nilable(Codespaces::NetworkConfiguration))
  end
  def self.for(repository:, billable_owner:, actor:)
    if beta_feature_enabled?(billable_owner:)
      from_org_policy(repository:, billable_owner:)
    else
      nil
    end
  end

  sig do
    params(
      policy_owner: T.any(User, Business),
    ).returns(T::Array[Codespaces::NetworkConfiguration])
  end
  def self.list_for_policy_owner(policy_owner:)
    return [] unless policy_owner.present?
    if beta_feature_enabled?(billable_owner: policy_owner)
      enterprise = policy_owner.is_a?(Business) ? policy_owner : policy_owner.business
      list_for_enterprise(enterprise)
    else
      []
    end
  end

  sig { returns(NetworkBundle::NetworkConfigurationClient) }
  def self.client
    NetworkBundle::NetworkConfigurationClient.create
  end

  sig do
    params(
      enterprise: Business,
    ).returns(T::Array[Codespaces::NetworkConfiguration])
  end
  def self.list_for_enterprise(enterprise)
    networks = client.list_configurations(enterprise, "codespaces", "", true)
    networks.map do |network|
      new(id: network.id, name: network.name, enterprise: enterprise)
    end
  end
  private_class_method :list_for_enterprise

  sig do
    params(
      billable_owner: T.any(User, Business)
    ).returns(T::Boolean)
  end
  def self.beta_feature_enabled?(billable_owner:)
    # Network configurations can only be configured for orgs belonging to enterprises
    return false unless billable_owner.is_a?(Business) ||
      (billable_owner.organization? && billable_owner.respond_to?(:business) && billable_owner.business.present?)

    flag_target = billable_owner.is_a?(Business) ? billable_owner : billable_owner.business

    return true if flag_target.in_codespaces_salus_beta? && flag_target.feature_enabled?(:codespaces_vnet_injection_beta)

    false
  end
  private_class_method :beta_feature_enabled?

  sig do
    params(
      repository: Repository,
      billable_owner: User,
    ).returns(T.nilable(Codespaces::NetworkConfiguration))
  end
  def self.from_org_policy(repository:, billable_owner:)
    policy_params = Codespaces::NetworkConfigurationPolicy.get_network_configuration(
      repository: repository,
      billable_owner: billable_owner,
    )

    return nil unless policy_params

    new(id: policy_params["id"], name: policy_params["name"], enterprise: billable_owner.business)
  end
  private_class_method :from_org_policy

  sig do
    params(
      id: T.nilable(String),
      name: T.nilable(String),
      enterprise: T.nilable(Business),
      alpha: T::Boolean,
      repository: T.nilable(Repository),
      actor: T.nilable(User),
    ).void
  end
  def initialize(id:, name:, enterprise:, alpha: false, repository: nil, actor: nil)
    @id = T.let(id, T.nilable(String))
    @name = T.let(name, T.nilable(String))
    @enterprise = T.let(enterprise, T.nilable(Business))
  end

  sig { returns(T::Array[String]) }
  def regions
    subnets.keys
  end

  # Converts from the region names used by the network-service to
  # the Codespaces::Locations::Geo IDs used by the forms.
  sig { returns(T::Array[String]) }
  def geo_ids
    regions.map { |r| Codespaces::Locations::Region.find(r).geo.id }
  end

  sig { params(region: String).returns(String) }
  def subnet_id(region)
    subnets[region] ||
      (raise NotFoundForRegion.new("No network resource found for region #{region}"))
  end

  sig { void }
  def refresh_cache!
    subnets(force: true)
  end

  private

  sig { params(force: T::Boolean).returns(T::Hash[String, String]) }
  def subnets(force: false)
    GitHub.cache.fetch(cache_key, expires_in: 1.day, force: force) do
      if hydrated_network_config.nil?
        {}
      else
        T.must(hydrated_network_config).network_configuration.network_resources.map do |network_resource|
          [network_resource.location, network_resource.subnet_id]
        end.to_h
      end
    end
  end

  sig { returns(T.nilable(NetworkBundle::ComputeResourceConfiguration)) }
  def hydrated_network_config
    client.get_compute_resources(@enterprise, "codespaces", T.must(@id))
  end

  sig { returns(Integration) }
  def app
    ::Apps::Internal.integration(:codespaces_production)
  end

  sig { returns(NetworkBundle::NetworkConfigurationClient) }
  def client
    self.class.client
  end

  sig { returns(String) }
  def cache_key
    ["network-configuration", T.must(@enterprise).id, T.must(@id)].join(":")
  end
end
