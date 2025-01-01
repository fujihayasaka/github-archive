# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::AgreementsListComponent < ApplicationComponent
  extend T::Sig

  # agreements - a paginated list of SponsorsAgreement records
  sig { params(agreements: T.any(WillPaginate::Collection, ActiveRecord::Relation)).void }
  def initialize(agreements:)
    @agreements = agreements
  end

  private

  sig { returns(T::Boolean) }
  def render?
    GitHub.sponsors_enabled? && logged_in?
  end

  sig { returns(T.any(WillPaginate::Collection, ActiveRecord::Relation)) }
  memoize def agreements
    GitHub::PrefillAssociations.prefill_associations(@agreements, :organization)
    GitHub::PrefillAssociations.prefill_batch_method(@agreements, :total_active_signatures)
    @agreements
  end

  sig { returns T::Hash[T.nilable(Integer), T::Array[SponsorsAgreement]] }
  memoize def agreements_by_organization_id
    agreements.group_by(&:organization_id)
  end

  sig { returns T::Hash[Integer, T.nilable(Organization)] }
  memoize def orgs_by_id
    agreements.select(&:organization_id).map { |agreement| [agreement.organization_id, agreement.organization] }.to_h
  end

  sig { returns(T::Hash[String, T::Hash[T.nilable(Integer), String]]) }
  memoize def latest_version_by_kind_and_organization_id
    SponsorsAgreement.latest_version_by_kind_and_organization_id
  end

  sig { params(agreement: SponsorsAgreement).returns(T::Boolean) }
  def latest_version?(agreement)
    latest_versions = latest_version_by_kind_and_organization_id[agreement.kind]
    return true unless latest_versions # this agreement is the first of its kind
    agreement.version == latest_versions[agreement.organization_id]
  end
end
