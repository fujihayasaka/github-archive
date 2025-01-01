# typed: strict
# frozen_string_literal: true

class Businesses::Billing::SponsorshipsController < Businesses::BillingsController
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  sig { void }
  def index
    if this_business.billed_via_billing_platform?
      render "businesses/billing_platform/sponsorships", locals: { business: this_business }
    else
      render_404
    end
  end
end
