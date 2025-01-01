# typed: true
# frozen_string_literal: true

class Orgs::People::EnterpriseOwnersController < Orgs::Controller
  javascript_bundle :organizations

  before_action :login_required
  before_action :owning_business_required
  before_action :org_membership_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: %i(index),
    optional: true

  def index
    set_hovercard_subject(this_organization)

    respond_to do |format|
      format.html do
        instrument_index
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/enterprise_owners_table", locals: {
            view: create_view_model(Orgs::People::EnterpriseOwnersPageView,
              organization: this_organization,
              page: current_page,
              query: params[:query]
            )
          }
        else
          view = create_view_model(
            Orgs::People::EnterpriseOwnersPageView,
            organization: this_organization,
            page: current_page,
            query: params[:query]
          )
          render "orgs/people/enterprise_owner", locals: { view: view }
        end
      end
    end
  end

  private

  def owning_business_required
    render_404 unless this_organization.business
  end

  def org_membership_required
    render_404 unless viewer_is_member_of_this_org?
  end

  def instrument_index
    GlobalInstrumenter.instrument("organization.enterprise_owners_view", {
      enterprise: this_organization.business,
      organization: this_organization,
      actor: current_user,
    })
  end
end
