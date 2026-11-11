# typed: true
# frozen_string_literal: true

module OrganizationParamsHelper
  # Public: Get the user-given parameter for the login of the organization being accessed. Checks multiple parameters
  # to see which was provided. Use this method to ensure we prefer the same parameter in different places, so that
  # the org whose data we use is the same org whose access was checked for the viewer.
  #
  # Returns a String or nil.
  def org_login_param
    T.unsafe(self).params[:organization_id] || T.unsafe(self).params[:org]
  end
end
