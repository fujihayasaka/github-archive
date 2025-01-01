# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::InvoicedAgreementSignaturesController < StafftoolsController
  before_action :sponsors_required

  delegate :organization, to: :signature

  sig { void }
  def update
    success = signature.terminate

    if success
      flash[:notice] = "Successfully terminated #{organization}'s agreement signature. Admins and billing managers will be notified via email."
    else
      flash[:error] = "Unable to terminate #{organization}'s agreement signature."
    end

    redirect_to billing_stafftools_user_path(organization)
  end

  private

  sig { returns(SponsorsInvoicedAgreementSignature) }
  def signature
    SponsorsInvoicedAgreementSignature.find(params[:id])
  end
end
