# typed: true
# frozen_string_literal: true

class TeamsNotificationsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    only: [:watch_subscription]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  TEAM_PAGE_SIZE = 25

  def index
    return redirect_to watching_path unless GitHub.flipper[:ignorable_team_notifications].enabled?(current_user)

    unauthorized_teams_ids = cap_filter.unauthorized_resource_ids(current_user.teams)

    teams = current_user.teams.joins(:organization)
                              .where.not(id: unauthorized_teams_ids)
                              .order("users.login ASC, teams.name ASC")
                              .paginate(page: teams_page, per_page: TEAM_PAGE_SIZE)

    render("notifications/teams/index", locals: { teams: teams })
  end

  # Change the user subscription status for a team
  def create
    return render_404 unless current_team

    case params[:reason]
    when "included"   then current_user.unsubscribe_team(current_team)
    when "subscribed" then current_user.subscribe_team(current_team)
    when "ignore"     then current_user.ignore_team(current_team)
    end

    subscription = current_team.subscription_status(current_user)

    render(Teams::NotificationsComponent.new(
      team: current_team,
      status: subscription,
      deferred: false,
      beta: params[:beta] == "true",
      button_size: params[:button_size]
    ), layout: false)
  end

  def watch_subscription # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless GitHub.flipper[:notifications_async_watch_team_button].enabled?(current_user)
    return head :not_found unless current_organization

    # Can a user 'watch_subscription' for a team they are not a member of?
    # team is returned here without any checks if the user is a member of the org or of the team.
    team = current_organization.teams.find_by_slug(params[:team])
    return head :not_found if !team

    subscription = team.subscription_status(current_user)

    render(Teams::NotificationsComponent.new(
      team: team,
      status: subscription,
      deferred: false,
      beta: params[:beta] == "true",
      button_size: params[:button_size]
    ), layout: false)
  end

  private

  memoize def current_organization
    if params[:org]
      Organization.find_by_login(params[:org])
    end
  end

  helper_method :teams_page
  memoize def teams_page
    [params[:page].to_i, 1].max
  end

  memoize def current_team
    current_user.teams.find_by_id(params[:team_id].to_i)
  end

  def target_for_conditional_access
    case params[:action]
    when "index"
      # index uses a CAP filter
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    when "create", "watch_subscription"
      # cap_bypass:to_fix
      # Consider the case when current_user is not a member of the team identified by params[:team_id]?
      # current_team would be nil and CAP is bypassed.
      # 'create' will 404 if current_team is nil, so this is safe for 'create'
      # However, 'watch_subscription' does not operate on 'current_team'. This bypasses CAP, and potentially allows other types of unauthorized access.
      return :no_target_for_conditional_access unless current_team # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_team.target_for_conditional_access
    end
  end
end
