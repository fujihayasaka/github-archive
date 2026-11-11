# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::NetworkConfigurationComponent < ApplicationComponent
  include CodespacesHelper
  attr_reader :constraint, :existing_policy, :organization

  def initialize(constraint:, organization:, existing_policy: nil)
    @constraint = constraint
    @existing_policy = existing_policy
    @organization = organization
  end

  # Hide from enterprise-level policies until we add support for enterprise-level network configurations
  def render?
    @organization.is_a?(Organization)
  end

  memoize def existing_policy_constraint
    return unless existing_policy.present?
    existing_policy[:current_policy_constraints].find { |pc| pc[:name] == constraint[:name] }
  end

  memoize def save_button_disabled?
    !existing_policy_constraint
  end

  class FakeNetworkConfiguration
    attr_reader :id, :name
    def initialize(id, name)
      @id = id
      @name = name
    end
  end

  def available_network_configurations
    Codespaces::NetworkConfiguration.list_for_policy_owner(policy_owner: organization)
  end

  def existing_policy_has_selection?
    return false if existing_policy_constraint.nil?

    existing_policy_constraint[:params].present?
  end

  def selected_network_text
    return "" if existing_policy_constraint.nil? || existing_policy_constraint[:params].nil?
    existing_policy_constraint[:params]["name"]
  end

  def existing_policy_has_network_selected?(network_config_id)
    return false unless existing_policy_has_selection?
    existing_policy_constraint[:params]["id"] == network_config_id
  end
end
