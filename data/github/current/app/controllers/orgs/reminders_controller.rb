# typed: true
# frozen_string_literal: true

class Orgs::RemindersController < Orgs::Controller
  include RemindersMethods

  before_action :redirect_organization_members
  before_action :feature_enabled?
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :set_reminder!, only: [:show, :update, :destroy, :reminder_test]

  before_action { @selected_link = :settings_reminders }

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    only: [:repository_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:team_autocomplete]

  def index
    respond_to do |format|
      format.html do
        view = create_view_model(
          Reminders::IndexView,
          slack_workspaces: slack_workspaces,
          current_user: current_user,
          organization: this_organization,
          slack_installation: this_client_installation(:slack),
        )
        render "orgs/reminders/index", locals: { view: view }
      end
    end
  end

  # The rest of the controller methods are handled in `RemindersMethods`

  private

  def render_edit(reminder)
    respond_to do |format|
      format.html do
        view = create_view_model(
          ::Reminders::EditView,
          slack_workspaces: slack_workspaces,
          reminder: reminder,
        )
        render "orgs/reminders/edit", locals: { view: view }
      end
    end
  end

  def redirect_organization_members
    return unless this_organization

    if this_organization.member?(current_user) && !this_organization.adminable_by?(current_user)
      flash[:error] = "You must be an organization owner to manage organization reminders."
      redirect_back(fallback_location: user_path(this_organization))
    end
  end

  def feature_enabled?
    render_404 unless RemindersMethods.reminders_enabled?(this_organization)
  end
end
