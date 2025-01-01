# typed: true
# frozen_string_literal: true

class Businesses::AdminSuggestionsController < Businesses::BusinessController
  include BusinessesHelper

  before_action :manage_enterprise_admins_required
  before_action :non_scim_managed_business_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    if GitHub.bypass_business_member_invites_enabled? && GitHub.site_admin_role_managed_externally?
      return render_404
    end

    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      view = create_view_model(Businesses::Admins::SuggestionsView,
        business: this_business,
        query: params[:q],
        exclude_suspended: true
      )
      format.html_fragment do
        render partial: "businesses/admins/suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "businesses/admins/suggestions", locals: { view: view }
      end
    end
  end
end
