# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::InvoicedSponsorshipsController < StafftoolsController
  before_action :sponsors_required
  before_action :invoiced_sponsor_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    if request.xhr? || pjax?
      render Stafftools::Billing::InvoicedSponsorshipsComponent.new(
        sponsor: sponsor,
        page: current_page,
      ), layout: false
    else
      render "stafftools/sponsors/invoiced/invoiced_sponsorships/index", locals: {
        sponsor: sponsor,
        page: current_page,
      }
    end
  end

  private

  memoize def sponsor
    User.find_by!(login: params[:invoiced_sponsor_id])
  end

  def invoiced_sponsor_required
    render_404 unless sponsor&.sponsors_invoiced?
  end
end
