# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::InvoicedSponsorsController < StafftoolsController
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  SPONSORS_PER_PAGE = 10

  def index
    active_only = params[:active_only].blank? || params[:active_only] == "1"
    orgs = Organization.premium_sponsors(active_only: active_only).by_login
      .paginate(page: current_page, per_page: SPONSORS_PER_PAGE)

    respond_to do |format|
      format.html do
        if request.xhr?
          render Stafftools::Sponsors::Invoiced::ListComponent.new(
            orgs: orgs,
            active_only: active_only,
          ), layout: false
        else
          render "stafftools/sponsors/invoiced/index", locals: {
            orgs: orgs,
            active_only: active_only,
          }
        end
      end
    end
  end
end
