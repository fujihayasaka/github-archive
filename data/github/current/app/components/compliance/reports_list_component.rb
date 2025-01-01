# typed: true
# frozen_string_literal: true

class Compliance::ReportsListComponent < ApplicationComponent
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  private

  def render?
    helpers.compliance_reports_available_for_account?(account)
  end

  memoize def reports
    scope = ComplianceReport.published

    if account.is_a?(::Business)
      scope = scope.for_ghec_account
    elsif account.is_a?(::Organization)
      if account.business_plus?
        scope = scope.for_ghec_account
      else
        scope = scope.for_non_ghec_account
      end
    end

    scope.top_level_reports
  end
end
