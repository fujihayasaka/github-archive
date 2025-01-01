# typed: true
# frozen_string_literal: true

# The Enterprise Managed User Visibility policy makes sure access to resources
# inside the enterprise is unauthorized for any actor outside of the enterprise.
# If however SSO redirect is enabled for the enterprise, then the policy will
# redirect the actor to the target EMU enterprise SSO login page.
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::EmuVisibilityPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EmuVisibility

  # application controller specific enforcement implementation
  def emu_visibility_enforce(target)
    business = sso_redirect_business(target)
    if business.present?
      callback.send(:redirect_to, callback.business_idm_sso_enterprise_path(business, return_to: callback.request.url))
    else
      callback.send(:render_404)
    end
  end

  private

  def sso_redirect_business(target)
    business = business_for(target)
    return business if callback.request.get? && business&.sso_redirect_enabled?
  end
end
