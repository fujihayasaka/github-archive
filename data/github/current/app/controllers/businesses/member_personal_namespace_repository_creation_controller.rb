# typed: true
# frozen_string_literal: true

class Businesses::MemberPersonalNamespaceRepositoryCreationController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    if %w[0 1].include?(params[:restrict_create_repository_in_personal_namespace])
      message = if params[:restrict_create_repository_in_personal_namespace] == "1"
        this_business.enable_restrict_create_repository_in_personal_namespace(actor: current_user)
        "Users can no longer create repositories in their personal namespace inside this enterprise."
      else
        this_business.disable_restrict_create_repository_in_personal_namespace(actor: current_user)
        "Users can now create repositories in their personal namespace inside this enterprise."
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end
end
