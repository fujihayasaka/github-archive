# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::HostSetupComponent < ApplicationComponent
  include CodespacesHelper
  attr_reader :constraint, :existing_policy, :owner

  def initialize(constraint:, owner:, existing_policy: nil)
    @constraint = constraint
    @existing_policy = existing_policy
    @owner = owner
  end

  memoize def existing_policy_constraint
    return unless existing_policy.present?
    existing_policy[:current_policy_constraints].find { |pc| pc[:name] == constraint[:name] }
  end

  memoize def existing_selected_repo
    return "None" if existing_policy_constraint.nil?
    existing_policy_constraint[:params]["repo"] || "None"
  end

  memoize def existing_selected_branch
    return "None" if existing_policy_constraint.nil?
    existing_policy_constraint[:params]["branch"] || "None"
  end

  memoize def existing_selected_path
    return "" if existing_policy_constraint.nil?
    existing_policy_constraint[:params]["path"] || ""
  end

  memoize def hide_branch_selector?
    existing_selected_branch == "None"
  end

  memoize def hide_path_selector?
    existing_selected_path == ""
  end

  memoize def existing_values_text
    return "None" if existing_policy_constraint.nil? || existing_policy_constraint[:params].nil?
    "#{GitHub.url}/#{existing_selected_repo}/blob/#{existing_selected_branch}/#{existing_selected_path}"
  end

  memoize def save_button_disabled?
    !existing_policy_constraint
  end

  memoize def repo_select_path
    if owner.is_a?(Organization)
      dotfiles_repository_select_codespaces_path(repos_owned_by: owner.id)
    elsif owner.is_a?(Business)
      settings_codespaces_host_setup_repository_select_enterprise_path
    end
  end

  def repo_search_placeholder
    if owner.is_a?(Business)
      "Search for a repository (exclude org)"
    else
      "Search for a repository"
    end
  end
end
