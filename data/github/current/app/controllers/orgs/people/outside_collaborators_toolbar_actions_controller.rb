# typed: true
# frozen_string_literal: true

class Orgs::People::OutsideCollaboratorsToolbarActionsController < Orgs::Controller
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
        render partial: "orgs/people/outside_collaborators_toolbar_actions", locals: {
          organization: this_organization,
          selected_outside_collaborators: selected_outside_collaborators,
        }
      end
    end
  end

  private

  def selected_outside_collaborators
    Scientist.run("break-outside-collaborators-toolbar-actions-join") do |e|
      e.compare_record_sequence
      e.use { this_organization.outside_collaborators.where(id: params[:outside_collaborator_ids] || []).load }
      e.try do
        outside_collaborator_ids = params[:outside_collaborator_ids] || []
        ids = this_organization.outside_collaborator_ids(actor_ids: outside_collaborator_ids)
        User.where(id: ids).load
      end
    end
  end
end
