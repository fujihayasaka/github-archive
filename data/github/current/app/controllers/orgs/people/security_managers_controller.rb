# typed: true
# frozen_string_literal: true

class Orgs::People::SecurityManagersController < Orgs::Controller
  before_action :login_required
  before_action :organization_read_required

  def index
    # Adds organization membership to the page's user hovercards
    set_hovercard_subject(this_organization)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/security_managers_table", locals: {
            view: create_view_model(Orgs::People::SecurityManagersPageView,
              organization: this_organization,
              page: current_page,
              query: params[:query]
            )
          }
        else
          view = create_view_model(
            Orgs::People::SecurityManagersPageView,
            organization: this_organization,
            page: current_page,
            query: params[:query],
          )
          render "orgs/people/security_managers", locals: { view: view }
        end
      end
    end
  end

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i(index)
end
