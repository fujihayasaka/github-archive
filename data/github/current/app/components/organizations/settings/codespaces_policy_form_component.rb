# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyFormComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :owner, :existing_policy

  def initialize(owner:, existing_policy: nil)
    @owner = owner
    @existing_policy = existing_policy
  end

  def owner_display_name
    enterprise_owner? ? owner.slug : owner.display_login
  end

  def enterprise_owner?
    owner.is_a?(Business)
  end

  def render?; true; end

  def hide_add_constraints_info?
    return false if existing_policy.nil?

    existing_policy[:current_policy_constraints].any?
  end

  def hide_constraints_list?
    return true if existing_policy.nil?

    existing_policy[:current_policy_constraints].empty?
  end

  def hide_constraint_row?(constraint_name)
    return true if existing_policy.nil?

    existing_policy[:current_policy_constraints].none? do |constraint|
      constraint[:name] == constraint_name
    end
  end

  def hide_selected_repos_count_element?
    existing_policy.nil? || existing_policy[:targets_all_repositories?]
  end

  def selected_repos_count
    return 0 if existing_policy.nil?
    return 0 if existing_policy[:targets_all_repositories?]
    return 0 if existing_policy[:targeted_repository_ids].nil?

    existing_policy[:targeted_repository_ids].count
  end

  def csrf_token
    if existing_policy.present?
      authenticity_token_for(submit_url, method: :put)
    else
      authenticity_token_for(submit_url)
    end
  end

  def submit_url
    if enterprise_owner?
      if existing_policy.present?
        settings_codespaces_update_policy_group_enterprise_path(slug: owner.slug, identifier: existing_policy[:id])
      else
        settings_codespaces_create_policy_group_enterprise_path(slug: owner.slug)
      end
    else
      if existing_policy.present?
        settings_org_codespaces_update_policy_path(organization_id: owner, identifier: existing_policy[:id])
      else
        settings_org_codespaces_create_policy_path(organization_id: owner)
      end
    end
  end

  def redirect_url
    if enterprise_owner?
      settings_codespaces_policies_enterprise_path(slug: owner.slug)
    else
      settings_org_codespaces_policies_path(organization_id: owner)
    end
  end

  def edit_url(policy_group)
    if enterprise_owner?
      settings_codespaces_edit_policy_group_enterprise_path(owner, policy_group)
    else
      settings_org_codespaces_policies_edit_path(owner, policy_group)
    end
  end

  def add_constraint_dropdown_url
    if enterprise_owner?
      settings_codespaces_add_constraint_dropdown_enterprise_path(owner)
    else
      settings_org_codespaces_policies_add_constraint_dropdown_url(owner)
    end
  end

  def policy_member_target_list_url
    if enterprise_owner?
      if existing_policy.present?
        settings_codespaces_org_dialog_list_enterprise_path(slug: owner.slug, identifier: existing_policy[:id])
      else
        settings_codespaces_org_dialog_list_enterprise_path(slug: owner.slug)
      end
    else
      if existing_policy.present?
        settings_org_codespaces_policies_repo_dialog_list_path(organization_id: owner, identifier: existing_policy[:id])
      else
        settings_org_codespaces_policies_repo_dialog_list_path(organization_id: owner)
      end
    end
  end

  def owner_model_type
    enterprise_owner? ? Codespaces::PolicyGroupMembership::TARGET_TYPE_BUSINESS : Codespaces::PolicyGroupMembership::TARGET_TYPE_USER
  end

  def child_target_model_type
    enterprise_owner? ? Codespaces::PolicyGroupMembership::TARGET_TYPE_USER : Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY
  end

  def child_target_type
    enterprise_owner? ? "Organizations" : "Repositories"
  end

  def child_target_description
    enterprise_owner? ? "organizations within your enterprise" : "repositories within your organization"
  end

  memoize def existing_all_repos_host_setup_policy
    records = Codespaces::PolicyGroupMembership.includes(:policy_group).joins(:policy_constraints).where(target: owner, policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP })
    if existing_policy.present?
      records = records.where.not(policy_group_id: existing_policy[:id])
    end
    records.first&.policy_group
  end

  memoize def existing_all_repos_network_configuration_policy
    records = Codespaces::PolicyGroupMembership.includes(:policy_group).joins(:policy_constraints).where(target_id: owner.id, policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION })
    if existing_policy.present?
      records = records.where.not(policy_group_id: existing_policy[:id])
    end
    records.first&.policy_group
  end

  def all_repos_host_setup_policy_exists?
    existing_all_repos_host_setup_policy.present?
  end

  def all_repos_network_configuration_policy_exists?
    existing_all_repos_network_configuration_policy.present?
  end

  memoize def repo_ids_host_setup
    ids = Codespaces::PolicyGroupMembership.joins(:policy_constraints, :policy_group).
      where(
        target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY,
        policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP },
        policy_group: { owner: owner }).
      map(&:target_id)

    if existing_policy.present?
      ids - existing_policy[:targeted_repository_ids]
    else
      ids
    end
  end

  memoize def repo_ids_network_configuration
    ids = Codespaces::PolicyGroupMembership.joins(:policy_constraints, :policy_group).
      where(
        target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY,
        policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION },
        policy_group: { owner: }).
      map(&:target_id)

    if existing_policy.present?
      ids - existing_policy[:targeted_repository_ids]
    else
      ids
    end
  end

  memoize def codespaces_host_setup_policy_enabled?
    owner.in_codespaces_salus_beta? && owner.feature_enabled?(:codespaces_host_setup_policy)
  end

  memoize def codespaces_network_configuration_policy_enabled?
    Codespaces::OrgPolicy.new(user: nil, org: owner).org_admin_can_configure_private_networking?
  end

  memoize def track_when_policy_targets_all_repositories?
    codespaces_host_setup_policy_enabled? || codespaces_network_configuration_policy_enabled?
  end

  private

  def current_policy_constraint_names
    return unless existing_policy
    existing_policy[:current_policy_constraints].map { |constraint| constraint[:name] }
  end

  memoize def constraints
    Codespaces::PolicyConstraint.config_for_policy_owner(owner)
  end
end
