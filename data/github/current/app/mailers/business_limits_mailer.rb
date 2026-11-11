# typed: true
# frozen_string_literal: true

class BusinessLimitsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/business_limits"

  layout "layouts/primer_layout"

  def at_organizations_limit(business)
    @business = business

    subject = "[GitHub] Organizations limit reached for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def at_organizations_soft_limit(business)
    @business = business
    @organizations_count = business.organizations_limit_counter

    subject = "[GitHub] Organizations limit approaching for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def at_members_limit(business)
    @business = business

    subject = "[GitHub] Members limit reached for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def at_members_soft_limit(business)
    @business = business
    @members_count = business.members_limit_counter

    subject = "[GitHub] Members limit approaching for #{@business.name}"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end
end
