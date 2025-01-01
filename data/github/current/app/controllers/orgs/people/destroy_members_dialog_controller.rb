# typed: true
# frozen_string_literal: true

class Orgs::People::DestroyMembersDialogController < Orgs::Controller
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
  javascript_bundle :organizations

  def show
    selected_members = this_organization.visible_users_for(current_user, actor_ids: params[:member_ids])

    respond_to do |format|
      format.html do
        render partial: "orgs/people/destroy_members_dialog", locals: {
          view: create_view_model(Orgs::People::DestroyMembersDialogView,
            organization: this_organization,
            selected_members: selected_members,
            redirect_to_path: params[:redirect_to_path]
          )
        }
      end
    end
  end
end
