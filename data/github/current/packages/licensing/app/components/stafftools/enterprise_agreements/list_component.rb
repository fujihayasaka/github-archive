# typed: strict
# frozen_string_literal: true

class Stafftools::EnterpriseAgreements::ListComponent < ApplicationComponent
  sig { params(business: Business).void }
  def initialize(business:)
    @business = T.let(business, ::Business)
  end

  sig { returns(T::Hash[String, Integer]) }
  memoize def billable_seats_per_agreement
    @business.consumed_volume_licenses_per_agreement_count
  end

  sig { returns(T::Hash[String, Integer]) }
  memoize def non_linked_seats_per_agreement
    @business.unassigned_user_bundled_license_assignments_per_agreement_count
  end

  sig { returns(T::Array[Licensing::EnterpriseAgreement]) }
  memoize def enterprise_agreements
    @business.enterprise_agreements.to_a
  end
end
