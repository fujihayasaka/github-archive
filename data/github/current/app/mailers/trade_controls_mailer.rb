# typed: strict
# frozen_string_literal: true

class TradeControlsMailer < ApplicationMailer
  self.mailer_name = "mailers/trade_controls"

  helper :trade_controls, :text

  default from: -> { github_trade_appeals }
  default return_path: -> { github_trade_appeals }
  default subject: "GitHub and Trade Controls"

  sig { params(user: User).void }
  def individual_actor_restricted(user)
    mail(to: user_email(user))
  end

  sig { params(user: User).void }
  def individual_actor_reactivated(user)
    mail(to: user_email(user))
  end

  sig { params(org: Organization).void }
  def organization_restricted(org)
    mail(to: (admin_emails(org) | billing_emails(org)))
  end

  sig { params(org: Organization).void }
  def organization_reactivated(org)
    mail(to: (admin_emails(org) | billing_emails(org)))
  end
end
