# typed: true
# frozen_string_literal: true

module Organization::CodeScanningDependency
  extend T::Helpers
  requires_ancestor { Organization }

  def alerts_code_scanning_external_api_enabled?
    return false unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?

    advanced_security_purchased? || GitHub.dotcom_request?
  end

  def code_scanning_autofix_public_repo_enabled?
    feature_enabled?(:code_scanning_autofix_public_repo, memoize: false)
  end
end
