# typed: true
# frozen_string_literal: true

class Orgs::People::MembersToolbarActionsController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]
  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  before_action :login_required
  before_action :organization_admin_required

  def show
    respond_to do |format|
      format.html do
        render partial: "orgs/people/members_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::People::ToolbarActionsView,
              organization: this_organization,
              selected_members: this_organization.visible_users_for(current_user, actor_ids: params[:member_ids] || [])
            )
          }
      end
    end
  end
end
