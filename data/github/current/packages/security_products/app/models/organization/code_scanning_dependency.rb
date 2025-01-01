# typed: true
# frozen_string_literal: true

module Organization::CodeScanningDependency
  extend T::Helpers
  requires_ancestor { Organization }

  def alerts_code_scanning_external_api_enabled?
    return false unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
    return true if GitHub.dotcom_request?

    T.bind(self, Organization)
    bundled = advanced_security_products_bundled?
    (bundled && advanced_security_purchased?) || (!bundled && code_security_purchased?)
  end
end
