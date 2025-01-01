# typed: true
# frozen_string_literal: true

class Branch::BranchProtectionNotEnforcedWarningComponent < ApplicationComponent
  include HydroHelper
  include MemberFeatureRequestsHelper

  def initialize(repository:, branch: nil, link_to_branch_protections_page: true, feature: nil)
    @repository = repository
    @owner = repository.owner
    @branch = branch
    @link_to_branch_protections_page = link_to_branch_protections_page
    @feature = feature
  end

  def render?
    eligible_for_upsell?(feature: get_feature, requester: current_user, repo: @repository)
  end

  def action
    case
    when @feature == MemberFeatureRequest::Feature::Rulesets
      action = "you move to a GitHub Team organization account"

      if ask_admin_to_upgrade?
        action = "your organization admins upgrade this organization account to GitHub Team"
      elsif organization?
        action = "you upgrade this organization account to GitHub Team"
      end

      erb_template = <<~ERB
      The #{link_to_if link_to_branch_protections_page?, 'rulesets', repository_rulesets_path(owner, repository)} targeting your <strong>#{branch}</strong> branch won't be enforced on this private repository until #{action}.
      ERB

      sanitize(erb_template)
    else
      action = organization? ? "you upgrade your organization account to a GitHub Team or Enterprise account" : "you move to a GitHub Team or Enterprise organization account"

      erb_template = <<~ERB
      Your #{link_to_if link_to_branch_protections_page?, "protected branch rules", edit_repository_branches_path(owner, repository)} for your <strong>#{branch}</strong> branch won't be enforced on this private repository until #{action}.
      ERB

      sanitize(erb_template)
    end
  end

  def render_upgrade_cta?
    if organization?
      owner.adminable_by?(current_user)
    else
      repository.adminable_by?(current_user)
    end
  end

  def cta_path
    return helpers.settings_org_plans_path(owner) if organization?

    new_move_work_path(owner, repository: repository, feature: get_feature.to_s)
  end

  def get_feature
    @feature || MemberFeatureRequest::Feature::ProtectedBranches
  end

  def hydro_attributes
    if organization?
      analytics_click_attributes(category: "Change account", action: "compare plans", label: "location:branch_protection_not_enforced_warning_component,label:Upgrade")
    else
      analytics_click_attributes(category: "Migrate", action: "move to an organization", label: "location:branch_protection_not_enforced_warning_component,label:Move to an organization")
    end
  end

  private

  attr_reader :branch, :owner, :repository

  def organization?
    owner.organization?
  end

  def ask_admin_to_upgrade?
    organization? && !owner.adminable_by?(current_user)
  end

  def link_to_branch_protections_page?
    @link_to_branch_protections_page && repository.async_can_view_repository_settings?(current_user).sync
  end
end
