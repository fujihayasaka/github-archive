# typed: true
# frozen_string_literal: true

class TeamLimitsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/team_limits"

  layout "layouts/primer_layout"

  def at_members_limit(team)
    @team = team

    subject = "[GitHub] Members limit reached for the #{@team.name} team"

    premail \
      from: github,
      reply_to: github,
      bcc: team_authoritative_emails(@team),
      subject: subject
  end

  def at_members_soft_limit(team)
    @team = team
    @members_count = @team.members_limit_counter

    subject = "[GitHub] Members limit approaching for the #{@team.name} team"

    premail \
      from: github,
      reply_to: github,
      bcc: team_authoritative_emails(@team),
      subject: subject
  end
end
