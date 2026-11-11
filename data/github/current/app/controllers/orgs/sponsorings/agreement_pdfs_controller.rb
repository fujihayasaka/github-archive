# typed: true
# frozen_string_literal: true

class Orgs::Sponsorings::AgreementPdfsController < Orgs::Controller
  before_action :require_agreement
  before_action :require_organization

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,

  def show
    pdf = SponsorsAgreement::PdfRenderer.new(agreement: agreement).render

    send_data(
      pdf,
      filename: agreement.pdf_filename,
      type: "application/pdf",
    )
  end

  private

  def agreement
    SponsorsAgreement.find_by(id: params[:id])
  end

  def require_agreement
    render_404 unless agreement
  end

  def require_organization
    render_404 unless this_organization
  end
end
