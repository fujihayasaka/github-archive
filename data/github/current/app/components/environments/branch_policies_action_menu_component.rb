# typed: true
# frozen_string_literal: true
class Environments::BranchPoliciesActionMenuComponent < ApplicationComponent
  def initialize(environment:, repository:)
    @environment = environment
    @repository = repository
  end

  memoize def owner
    @repository.owner
  end

  memoize def protected_branches_policy?
    @environment.branch_policy_gate_branch_protected?
  end

  memoize def custom_branches_policy?
    !protected_branches_policy? && @environment.branch_policy_gate.present?
  end

  def no_branch_policy?
    !protected_branches_policy? && !custom_branches_policy?
  end

  def selected_button_text
    return "Protected branches only" if protected_branches_policy?
    return "Selected branches and tags" if custom_branches_policy?
    "No restriction"
  end

  def create_menu_item(menu:, label:, value:, description:, active:)
    menu.with_item(
      label: label,
      active: active,
      href: change_environment_branch_policy_type_path(repository: @repository, user_id: owner, environment_id: @environment.id),
      form_arguments: {
        method: :post,
        name: "type",
        value: value
      }
    ) do |item|
      item.with_description.with_content(description)
    end
  end
end
