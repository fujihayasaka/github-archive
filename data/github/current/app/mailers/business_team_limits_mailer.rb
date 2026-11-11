# typed: true
# frozen_string_literal: true

class BusinessTeamLimitsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/business_team_limits"

  layout "layouts/primer_layout"

  def at_business_teams_limit(business)
    @business = business

    subject = "[GitHub] Enterprise teams limit reached for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def at_business_teams_soft_limit(business)
    @business = business
    @business_teams_count = @business.business_teams_limit_counter

    subject = "[GitHub] Enterprise teams limit approaching for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def at_members_limit(team)
    @team = team

    subject = "[GitHub] Members limit reached for the #{@team.name} enterprise team"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@team.business),
      subject: subject
  end

  def at_members_soft_limit(team)
    @team = team
    @members_count = @team.members_limit_counter

    subject = "[GitHub] Members limit approaching for the #{@team.name} enterprise team"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@team.business),
      subject: subject
  end

  def at_organization_assignments_limit(team)
    @team = team

    subject = "[GitHub] Organization assignments limit reached for the #{@team.name} enterprise team"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@team.business),
      subject: subject
  end

  def at_organization_assignments_soft_limit(team)
    @team = team
    @organization_assignments_count = @team.organization_assignments_limit_counter

    subject = "[GitHub] Organization assignments limit approaching for the #{@team.name} enterprise team"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@team.business),
      subject: subject
  end
end
