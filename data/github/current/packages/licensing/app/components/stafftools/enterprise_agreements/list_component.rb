# typed: strict
# frozen_string_literal: true

class Stafftools::EnterpriseAgreements::ListComponent < ApplicationComponent
  sig { params(business: Business).void }
  def initialize(business:)
    @business = T.let(business, ::Business)
  end

  sig { returns(T::Boolean) }
  def render?
    !GitHub.enterprise?
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

  VssEventCountsPerAgreement = T.type_alias { T::Hash[String, { assign: Integer, revoke: Integer, other: Integer }] }

  sig { returns(VssEventCountsPerAgreement) }
  memoize def vss_events_per_agreement
    vss_agreement_ids = enterprise_agreements.select(&:visual_studio_bundle?).filter_map(&:agreement_id)
    return {} if vss_agreement_ids.empty?

    Licensing::Vss::VssSubscriptionEvent
      .counts_by_agreement(vss_agreement_ids)
      .each_with_object({}) do |row, hash|
        key = row[:enterprise_agreement_number] || ""
        hash[key] = {
          assign: row[:assign_count].to_i,
          revoke: row[:revoke_count].to_i,
          other: row[:other_count].to_i,
        }
      end
  end
end
