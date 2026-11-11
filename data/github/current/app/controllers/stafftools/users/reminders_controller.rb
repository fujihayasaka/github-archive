# typed: true
# frozen_string_literal: true

class Stafftools::Users::RemindersController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  # We're defining this_user via prompt_for_hubber_access, which is not run in enterprise mode.
  # Following suite with other stafftools controller, ensure_user_exists is being run
  # in enterprise mode to make sure this_user is properly set.
  if GitHub.enterprise?
    before_action :ensure_user_exists, only: [:index]
  end

  def index
    if this_user.organization?
      render_org_reminders
    else
      render_user_reminders
    end
  end

  private

  def render_org_reminders
    scoped_reminders = Reminder.for_remindable(this_user)
    scoped_reminders = scoped_reminders.with_repo_nwo(params[:repo_query]) if params[:repo_query].present?
    scoped_reminders = scoped_reminders.where(id: params[:id_query].split(",").map(&:strip)) if params[:id_query].present?

    paginated_reminders =
      scoped_reminders.paginate(page: params[:page], per_page: 10).order_by_workspace

    reminders_by_workspace =
      paginated_reminders.select("reminders.*, reminder_slack_workspaces.name AS slack_workspace_name")
                         .group_by(&:slack_workspace_name)

    render "stafftools/users/reminders/index", locals: {
      paginated_reminders: paginated_reminders,
      reminders_by_workspace: reminders_by_workspace,
      user: this_user
    }
  end

  def render_user_reminders
    scoped_reminders = PersonalReminder.where(user: this_user)
    scoped_reminders = scoped_reminders.where(id: params[:id_query].split(",").map(&:strip)) if params[:id_query].present?

    paginated_reminders =
      scoped_reminders.paginate(page: params[:page], per_page: 10).order_by_workspace

    reminders_by_workspace =
      paginated_reminders.select("personal_reminders.*, reminder_slack_workspaces.name AS slack_workspace_name")
                         .group_by(&:slack_workspace_name)

    render "stafftools/users/reminders/index", locals: {
      paginated_reminders: paginated_reminders,
      reminders_by_workspace: reminders_by_workspace,
      user: this_user
    }
  end
end
