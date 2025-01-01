# typed: true
# frozen_string_literal: true

class Businesses::DefaultRepositoryPermissionController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    valid_values = Configurable::DefaultRepositoryPermission.valid_values.map(&:to_s) + ["no_policy"]
    permission = params[:default_repository_permission]&.to_s
    validate_setting value: permission, valid_values: valid_values

    message = ""
    if "no_policy" == permission
      this_business.clear_default_repository_permission(actor: current_user)
      message = "The base repository permission policy is removed."
    else
      begin
        permission = permission.to_sym
        this_business.update_default_repository_permission permission, force: true, actor: current_user
        message = "The base repository permission is set to \
          \"#{Configurable::DefaultRepositoryPermission.human_friendly_value(permission)}\" \
          and is enforced for this enterprise.".squish
      rescue Configurable::DefaultRepositoryPermission::AlreadyUpdating
        flash[:error] = "The base repository permission is already being updated."
        return redirect_to settings_member_privileges_enterprise_path(this_business)
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end
end
