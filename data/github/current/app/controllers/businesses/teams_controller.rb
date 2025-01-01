# typed: true
# frozen_string_literal: true

class Businesses::TeamsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    view = create_view_model(
      Businesses::Settings::TeamsView,
      business: this_business,
      params: params
    )
    render "businesses/settings/teams", locals: { view: view }
  end

  def update_team_discussions_allowed # rubocop:todo GitHub/UseRestfulActions
    enabled = params[:team_discussions_allowed]&.to_s
    validate_setting value: enabled

    message = ""
    case enabled
    when "enabled"
      this_business.allow_team_discussions(true, actor: current_user)
      message = "Team discussions are enabled and enforced for this enterprise."
    when "disabled"
      this_business.disallow_team_discussions(true, actor: current_user)
      message = "Team discussions are disabled and enforced for this enterprise."
    when "no_policy"
      this_business.clear_team_discussions_setting(actor: current_user)
      message = "Team discussions policy removed."
    end

    redirect_to settings_teams_enterprise_path(this_business), notice: message
  end
end
