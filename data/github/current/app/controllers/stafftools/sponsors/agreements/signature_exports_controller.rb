# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Agreements::SignatureExportsController < StafftoolsController
  before_action :sponsors_required
  before_action :ensure_invoiced_agreement

  OPTION_PARAM = :option

  sig { void }
  def create
    filename = "sponsors-agreement-signatures-export-#{export_option.serialize}-#{Date.current}.csv"

    data = CSV.generate do |csv|
      csv << %w(organization signed_by date_signed expiration)

      signatures.each do |signature|
        csv << [
          signature.safe_organization.display_login,
          signature.safe_signatory.display_login,
          signature.created_at,
          signature.expires_on,
        ]
      end
    end

    send_data data, type: "text/csv", disposition: "attachment; filename=#{filename}"
  end

  private

  sig { returns(SponsorsAgreement) }
  memoize def agreement
    SponsorsAgreement.find(params[:agreement_id])
  end

  sig { void }
  def ensure_invoiced_agreement
    render_404 unless agreement.invoiced_sponsor_kind?
  end

  sig { returns(SponsorsAgreement::Signatures::ExportOption) }
  memoize def export_option
    SponsorsAgreement::Signatures::ExportOption.try_deserialize(
      params[:option]
    ) || SponsorsAgreement::Signatures::ExportOption::All
  end

  sig { returns(T.any(T::Array[SponsorsInvoicedAgreementSignature], ActiveRecord::Relation)) }
  memoize def signatures
    signatures = agreement.invoiced_signatures.includes(:organization, :signatory)

    case export_option
    when SponsorsAgreement::Signatures::ExportOption::SignedInLastWeek
      signatures = signatures.where("created_at >= ?", 7.days.ago)
    when SponsorsAgreement::Signatures::ExportOption::ExpiresInNextWeek
      signatures = signatures.where("expires_on <= ?", 7.days.from_now.to_date)
    end

    signatures
  end
end
