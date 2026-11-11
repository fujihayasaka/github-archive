# typed: true
# frozen_string_literal: true

class Orgs::DefaultBranchSettingsController < Orgs::Controller
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    if current_organization.custom_default_new_repo_branch_enforced?
      flash[:error] = "Could not update default branch name preference, " \
        "default branch name preference enforced at the enterprise level."
      return redirect_to settings_org_repo_defaults_path
    end

    raw_name = params[:default_branch_name]

    if raw_name.blank?
      flash[:error] = "Could not update default branch name preference, " \
        "no branch name given."
    else
      normalized_name = Git::Ref.normalize(raw_name)

      if normalized_name.blank?
        flash[:error] = "Could not update default branch name preference, " \
          "'#{raw_name}' is not a valid branch name."
      elsif normalized_name == current_organization.custom_default_new_repo_branch
        flash[:notice] = "#{current_organization.display_login}'s default branch name is already #{normalized_name}."
      elsif current_organization.set_default_new_repo_branch(normalized_name, actor: current_user)
        flash[:notice] = "New repositories created in #{current_organization.display_login} will use " \
          "#{normalized_name} as their default branch."
      else
        flash[:error] = "Could not set the default branch name preference for " \
          "#{current_organization.display_login} at this time."
      end
    end

    redirect_to settings_org_repo_defaults_path
  end
end
