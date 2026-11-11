# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationProfilesController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_org_not_user

  def update
    org_profile = this_user.organization_profile || this_user.build_organization_profile
    org_profile.assign_attributes(org_profile_params)

    if org_profile.save
      flash[:notice] = "Updated #{this_user}'s organization profile record."
    else
      error = org_profile.errors.full_messages.to_sentence
      flash[:error] = "Could not update #{this_user}'s organization profile record: #{error}"
    end

    redirect_back(fallback_location: stafftools_user_path(this_user))
  end

  private

  memoize def org_profile_params
    params.require(:organization_profile).permit(:stripe_customer_id)
  end
end
