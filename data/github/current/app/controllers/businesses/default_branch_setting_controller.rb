# typed: true
# frozen_string_literal: true

class Businesses::DefaultBranchSettingController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    enforce = params[:default_branch_enforce] == "1"
    raw_name = params[:default_branch_name]
    is_enforce_changing = enforce != this_business.custom_default_new_repo_branch_enforced?

    if raw_name.blank?
      flash[:error] = "Could not update default branch name preference, no branch name given."
    else
      normalized_name = Git::Ref.normalize(raw_name)
      is_name_changing = normalized_name != this_business.custom_default_new_repo_branch

      if normalized_name.blank?
        flash[:error] = "Could not update default branch name preference, '#{raw_name}' is not a valid branch name."
      elsif !is_name_changing && !is_enforce_changing
        flash[:notice] = "#{this_business}'s default branch name is already #{normalized_name}."
      elsif this_business.set_default_new_repo_branch(normalized_name, actor: current_user, enforce: enforce)
        flash[:notice] = if is_name_changing
          "New repositories created in #{this_business} will use " \
          "#{normalized_name} as their default branch. Organizations will#{' not' if enforce} " \
          "be able to override this."
        elsif enforce
          "#{this_business}'s default branch name of #{normalized_name} is now enforced."
        else
          "#{this_business}'s default branch name of #{normalized_name} is no longer enforced."
        end
      else
        flash[:error] = "Could not set the default branch name preference for #{this_business} at this time."
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business)
  end
end
