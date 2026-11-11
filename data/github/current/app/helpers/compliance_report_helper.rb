# typed: true
# frozen_string_literal: true

module ComplianceReportHelper
  # Are compliance reports available for the given account?
  #
  # account - Organization or Business object
  #
  # Returns Boolean
  def compliance_reports_available_for_account?(account)
    return false unless GitHub.compliance_reports_available?

    account.is_a?(::Business) || account.is_a?(::Organization)
  end

  # Get the download path for a report based on an account and report slug.
  #
  # account - Organization or Business object
  # slug - String representing a report slug.
  #
  # Returns String
  def registered_compliance_report_path(account, slug)
    if account.is_a?(::Business)
      UrlHelpers.enterprise_compliance_report_path(account, key: slug)
    elsif account.is_a?(::Organization)
      UrlHelpers.org_compliance_report_path(account, key: slug)
    end
  end
end
