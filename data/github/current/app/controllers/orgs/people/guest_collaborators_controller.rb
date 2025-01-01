# typed: true
# frozen_string_literal: true

class Orgs::People::GuestCollaboratorsController < Orgs::Controller
  include Orgs::Invitations::RateLimiting

  before_action :login_required
  before_action :organization_admin_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    only: [:index]
  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    if this_organization.enterprise_managed_user_enabled?
      return render_404 unless current_user&.enterprise_managed_business == this_organization.business
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/members_table", locals: {
            view: create_view_model(Orgs::People::IndexPageView,
              organization: this_organization,
              page: current_page,
              query: params[:query]
            ),
            only_should_show_guest_collaborators: true
          }
        else
          view = create_view_model(
            Orgs::People::IndexPageView,
            organization: this_organization,
            finished_migration: params[:finished_migration] == "1",
            page: current_page,
            query: params[:query],
            rate_limited: org_invite_rate_limited?,
          )
          render "orgs/people/index", locals: { view: view, only_should_show_guest_collaborators: true }
        end
      end
    end
  end
end
