# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::AddConstraintComponent < ApplicationComponent

  attr_reader :current_policy_constraint_names, :owner, :all_repos_target, :all_repos_host_setup_policy_exists, :all_repos_network_configuration_policy_exists

  def initialize(owner:, current_policy_constraint_names:, all_repos_target:, all_repos_host_setup_policy_exists:, all_repos_network_configuration_policy_exists:)
    @owner = owner
    @current_policy_constraint_names = current_policy_constraint_names || []
    @all_repos_target = all_repos_target
    @all_repos_host_setup_policy_exists = all_repos_host_setup_policy_exists
    @all_repos_network_configuration_policy_exists = all_repos_network_configuration_policy_exists
  end

  memoize def constraint_config
    Codespaces::PolicyConstraint.config_for_policy_owner(owner)
  end

  memoize def constraints
    configs = constraint_config.reject do |name, config|
      config[:disabled] || config[:hidden] || name.in?(current_policy_constraint_names)
    end

    configs.map do |name, config|
      [
        name,
        config.slice(:name, :display_name, :type, :description, :allowable_values, :maximum_allowable_value, :minimum_allowable_value, :disabled_note, :isolate_constraint_to_a_single_policy, :global_target_only)
      ]
    end.to_h
  end

  def disabled_note_for(constraint_name)
    return constraint_config.dig(constraint_name, :disabled_note) unless constraint_config.dig(constraint_name, :isolate_constraint_to_a_single_policy)

    return unless disabled_constraint_names.any? do |name|
      constraint_config.dig(name, :isolate_constraint_to_a_single_policy)
    end

    if current_policy_constraint_names.any?
      "Note: Policies that include this constraint cannot include any other constraints"
    elsif all_repos_target &&
      ((all_repos_host_setup_policy_exists && constraint_name == Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP) ||
      (all_repos_network_configuration_policy_exists && constraint_name == Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION))
      "Note: This constraint can only be added once for 'All repositories' policy target"
    end
  end

  def org_admin_can_configure_private_networking?
    owner.is_a?(Organization) && Codespaces::OrgPolicy.new(org: owner, user: nil).org_admin_can_configure_private_networking?
  end

  def disabled_constraint_names
    constraint_names = []
    if owner.in_codespaces_salus_beta? && owner.feature_enabled?(:codespaces_host_setup_policy)
      if current_policy_constraint_names.any?
        constraint_names.append(Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)
      end

      if all_repos_host_setup_policy_exists && all_repos_target
        constraint_names.append(Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)
      end
    end

    if org_admin_can_configure_private_networking?
      if current_policy_constraint_names.any?
        constraint_names.append(Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      end

      if all_repos_network_configuration_policy_exists && all_repos_target
        constraint_names.append(Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      end
    end

    unless all_repos_target
      constraint_names.append(Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
    end

    constraint_names
  end

  def should_be_hidden?
    current_policy_constraint_names.each do |name|
      if Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.dig(name, :isolate_constraint_to_a_single_policy)
        return true
      end
    end
    false
  end
end
