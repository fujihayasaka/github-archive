# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::InvoicedAgreementSignaturesController < Orgs::Sponsorings::InvoicedBilling::BaseController
  extend T::Sig

  before_action :require_signature, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    org = T.must(signature).organization
    render "orgs/sponsorings/invoiced_agreement_signatures/show", layout: "application", locals: {
      signature: signature,
      sponsor: org,
    }
  end

  private

  sig { returns(T.nilable(SponsorsInvoicedAgreementSignature)) }
  memoize def signature
    SponsorsInvoicedAgreementSignature.for_org(this_organization).includes(:agreement, :signatory).find_by(id: params[:id])
  end

  sig { void }
  def require_signature
    render_404 unless signature.present?
  end
end
