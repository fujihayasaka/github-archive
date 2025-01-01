# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::SuggestionsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :business_owner_required
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      view = create_view_model(Businesses::OrganizationInvitations::SuggestionsView,
        orgs_only: true, business: this_business, query: params[:q])
      format.html_fragment do
        render partial: "businesses/organization_invitations/suggestions",
          formats: :html,
          locals: { view: view }
      end
      format.html do
        render partial: "businesses/organization_invitations/suggestions",
          locals: { view: view }
      end
    end
  end
end
