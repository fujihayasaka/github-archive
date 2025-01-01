# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::SignatureListComponent < ApplicationComponent
  extend T::Sig

  # signatures - a paginated list of SponsorsInvoicedAgreementSignature records
  sig do params(
    agreement: SponsorsAgreement,
    signatures: T.any(WillPaginate::Collection, ActiveRecord::Relation),
  ).void
  end
  def initialize(agreement:, signatures:)
    @agreement = agreement
    @signatures = signatures
  end

  private

  sig { returns(SponsorsAgreement) }
  attr_reader :agreement

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled? && logged_in?
    agreement.invoiced_sponsor_kind?
  end

  sig { returns(T.any(WillPaginate::Collection, ActiveRecord::Relation)) }
  memoize def signatures
    GitHub::PrefillAssociations.prefill_associations(@signatures, :organization)
    GitHub::PrefillAssociations.prefill_associations(@signatures, :signatory)
    @signatures
  end
end
