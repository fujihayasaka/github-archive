# typed: true
# frozen_string_literal: true

class Businesses::PeopleBulkActionsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: %i(index)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    respond_to do |format|
      format.html do
        render Businesses::People::BulkActionToolbarComponent.new(
          business: this_business,
          selected_user_ids: (params[:user_ids]&.filter_map(&:presence) || []).map(&:to_i),
          show_remove: params[:show_remove] != "false"
        ), layout: false
      end
    end
  end

  def show
    headers["Cache-Control"] = "no-cache, no-store"
    view = create_view_model \
      Businesses::PeopleView,
      business: this_business,
      selected_user_ids: (params[:user_ids]&.filter_map(&:presence) || []).map(&:to_i)
    render partial: "businesses/people/actions_dialog", locals: { view: view }
  end

  def create
    action_verb = "#{params[:bulk_action].capitalize}ing"
    case params[:bulk_action]
    when "add"
      if bulk_action_organizations_and_users_present?
        BusinessBulkAddMembersToOrganizationsJob.perform_later(
          this_business,
          current_user,
          params[:organization_ids],
          params[:user_ids]
        )
      end
    when "remove"
      if bulk_action_organizations_and_users_present?
        BusinessBulkRemoveMembersFromOrganizationsJob.perform_later(
          this_business,
          current_user,
          params[:organization_ids],
          params[:user_ids]
        )
      end
      action_verb = "Removing"
    else
      return render_404
    end
    flash[:notice] = "#{action_verb} the selected users #{params[:bulk_action] == "add" ? "to" : "from"} the selected organizations. This may take a few minutes."
    redirect_to people_enterprise_path(this_business)
  end

  private

  def bulk_action_organizations_and_users_present?
    params[:user_ids].present? &&
    params[:user_ids].size > 0 &&
    params[:organization_ids].present? &&
    params[:organization_ids].size > 0
  end
end
