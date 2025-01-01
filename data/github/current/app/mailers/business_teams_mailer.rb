# typed: true
# frozen_string_literal: true

class BusinessTeamsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/business_teams"

  layout "layouts/primer_layout"

  def removed_from_team(user, business, team_name, team_destroyed: false)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team_name
    @team_destroyed = team_destroyed

    subject = if @team_destroyed
      %Q[The "#{@business.safe_profile_name}" enterprise team "#{@team_name}" has been deleted]
    else
      %Q[You've been removed from the "#{@business.safe_profile_name}" enterprise team "#{@team_name}"]
    end

    premail(
      from: github,
      to: user_email(@user),
      subject: subject
    )
  end
end
