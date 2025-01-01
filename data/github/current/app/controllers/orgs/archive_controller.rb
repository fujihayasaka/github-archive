# typed: strict
# frozen_string_literal: true

class Orgs::ArchiveController < Orgs::Controller
  before_action :org_admins_only

  sig { void }
  def create
    unless org_name_verification_valid?(params[:"verify-name"])
      flash[:error] = "You must type the name of the organization to confirm."
      return redirect_to organization_settings_path(current_organization.display_login)
    end

    unless current_organization.archive(current_user)
      flash[:error] = "Your organization #{current_organization.display_login} cannot be archived at this time."
      return redirect_to organization_settings_path(current_organization)
    end

    flash[:notice] = "Your organization #{current_organization.display_login} is being archived."
    redirect_to organization_settings_path(current_organization)
  end

  sig { void }
  def destroy
    unless org_name_verification_valid?(params[:"verify-name"])
      flash[:error] = "You must type the name of the organization to confirm."
      return redirect_to organization_settings_path(current_organization)
    end

    unless current_organization.unarchive(current_user)
      flash[:error] = "Your organization #{current_organization.display_login} cannot be unarchived at this time."
      return redirect_to organization_settings_path(current_organization)
    end

    flash[:notice] = "Your organization #{current_organization.display_login} has been unarchived."
    redirect_to organization_settings_path(current_organization)
  end

  private

  sig { params(org_name: String).returns(T::Boolean) }
  def org_name_verification_valid?(org_name)
    current_organization.display_login.casecmp?(org_name)
  end
end
