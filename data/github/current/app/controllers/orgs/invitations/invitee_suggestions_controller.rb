# typed: true
# frozen_string_literal: true

class Orgs::Invitations::InviteeSuggestionsController < Orgs::Controller
  include Orgs::InvitationsControllerMethods

  before_action :login_required
  before_action :organization_admin_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    only: [:index]

  def index
    headers["Cache-Control"] = "no-cache, no-store"
    view = create_view_model(Orgs::Invitations::InviteeSuggestionsView,
      exclude_suspended: true,
      include_business_orgs: true,
      organization: this_organization,
      prepend_friends: false,
      query: params[:q],
    )

    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/invitations/invitee_suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "orgs/invitations/invitee_suggestions", locals: { view: view }
      end
    end
  end
end
