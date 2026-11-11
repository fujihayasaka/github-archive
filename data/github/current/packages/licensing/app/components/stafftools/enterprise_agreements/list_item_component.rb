# typed: strict
# frozen_string_literal: true

class Stafftools::EnterpriseAgreements::ListItemComponent < ApplicationComponent
  sig { params(business: Business, enterprise_agreement: Licensing::EnterpriseAgreement, billable_licenses: T.nilable(Integer), non_linked_licenses: T.nilable(Integer)).void }
  def initialize(business:, enterprise_agreement:, billable_licenses: 0, non_linked_licenses: 0)
    @business = T.let(business, ::Business)
    @enterprise_agreement = T.let(enterprise_agreement, Licensing::EnterpriseAgreement)
    @billable_licenses = T.let(billable_licenses, T.nilable(Integer))
    @non_linked_licenses = T.let(non_linked_licenses, T.nilable(Integer))
  end
end
