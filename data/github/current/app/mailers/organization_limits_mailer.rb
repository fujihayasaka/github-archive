# typed: true
# frozen_string_literal: true

class OrganizationLimitsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/organization_limits"

  layout "layouts/primer_layout"

  def at_teams_limit(organization)
    @org = organization

    subject = "[GitHub] Teams limit reached for #{@org.safe_profile_name}"

    premail \
      from: github,
      reply_to: github,
      bcc: admin_emails(@org),
      subject: subject
  end

  def at_teams_soft_limit(organization)
    @org = organization
    @teams_count = @org.teams_limit_counter

    subject = "[GitHub] Teams limit approaching for #{@org.safe_profile_name}"

    premail \
      from: github,
      reply_to: github,
      bcc: admin_emails(@org),
      subject: subject
  end

  def at_members_limit(organization)
    @org = organization

    subject = "[GitHub] Members limit reached for #{@org.safe_profile_name}"

    premail \
      from: github,
      reply_to: github,
      bcc: admin_emails(@org),
      subject: subject
  end

  def at_members_soft_limit(organization)
    @org = organization
    @members_count = @org.members_limit_counter

    subject = "[GitHub] Members limit approaching for #{@org.safe_profile_name}"

    premail \
      from: github,
      reply_to: github,
      bcc: admin_emails(@org),
      subject: subject
  end
end
