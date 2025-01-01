# typed: true
# frozen_string_literal: true

# The EnterpriseManagedUser policy makes sure access to resources outside the
# enterprise is unauthorized for a managed user
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::TenantVerificationPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::TenantVerification

  # application controller specific enforcement implementation
  def tenant_verification_enforce(target)
    business = sso_redirect_tenant
    if business.present?
      callback.send(:redirect_to, callback.business_idm_sso_enterprise_path(business, return_to: callback.request.url))
    else
      callback.send(:render_404)
    end
  end

  private

  def sso_redirect_tenant
    business = GitHub::CurrentTenant.get
    return business if callback.request.get? && business&.sso_redirect_enabled?
  end
end
