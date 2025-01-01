# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::BulkSponsorshipsController < Orgs::Sponsorings::BaseController
  before_action :ensure_user_can_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render "orgs/sponsorings/bulk_sponsorships/show", locals: {
      sponsor: this_organization,
    }
  end

  private

  sig { void }
  def ensure_user_can_access
    render_404 unless this_organization.billing_manageable_by?(current_user)
  end
end
