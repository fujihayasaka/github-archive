# typed: true
# frozen_string_literal: true

class Stafftools::Users::ActivitiesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    activity_view = Stafftools::User::ShowView.new(user: this_user, current_user: current_user)

    render "stafftools/users/activities/show", locals: { view: activity_view }
  end

  def destroy
    if clearing_all_activity?
      conduit_success = this_user.clear_events
      stratocaster_success = this_user.clear_all_timelines
      success = conduit_success || stratocaster_success

      if success
        flash[:notice] = "Cleared public and private activity for #{this_user}"
      else
        flash[:error] = "Could not clear activity for #{this_user}"
      end

      redirect_to stafftools_user_path(this_user)
    elsif clearing_public_activity?
      conduit_success = this_user.clear_events(public_only: true)

      timeline = this_user.events_key(type: :actor_public)
      stratocaster_success = GitHub.stratocaster.clear_timelines(timeline)

      if conduit_success || stratocaster_success
        flash[:notice] = "Cleared public activity for #{this_user.display_login}"
      else
        flash[:error] = "Could not clear public activity for #{this_user.display_login}"
      end

      redirect_to stafftools_user_path(this_user)
    else
      render_404
    end
  end

  private

  def clearing_all_activity?
    params[:type] == "all"
  end

  def clearing_public_activity?
    params[:type] == "public"
  end
end
