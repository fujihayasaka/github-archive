# typed: false
#frozen_string_literal: true

module TeamsHelper
  def watch_button_attributes(team_id, controller_action_slug)
    hydro_click_tracking_attributes("team.click",
      target: :WATCH_BUTTON,
      team_id: team_id,
    ).merge(
      "ga-click" => "Team, click Watch settings, action:#{controller_action_slug}",
    )
  end
end
