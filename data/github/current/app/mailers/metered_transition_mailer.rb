# typed: strict
# frozen_string_literal: true

class MeteredTransitionMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/metered_transition"

  layout "layouts/primer_layout"

  sig { params(transition: Licensing::LicensingModelTransition).void }
  def schedule(transition)
    @transition = T.let(transition, T.nilable(Licensing::LicensingModelTransition))
    @business = T.let(@transition&.business, T.nilable(Business))
    @subject = T.let("You've successfully scheduled your metered billing transition", T.nilable(String))
    @usage_based_billing_docs_url = T.let(usage_based_billing_docs_url, T.nilable(String))

    recipients = user_or_billing_recipients(@business)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: @subject
    )
  end

  sig { params(transition: Licensing::LicensingModelTransition).void }
  def day_before_notice(transition)
    @transition = T.let(transition, T.nilable(Licensing::LicensingModelTransition))
    @business = T.let(@transition&.business, T.nilable(Business))
    @subject = T.let("Reminder: Your transition to metered billing is tomorrow", T.nilable(String))
    @usage_based_billing_docs_url = T.let(usage_based_billing_docs_url, T.nilable(String))

    recipients = user_or_billing_recipients(@business)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: @subject
    )
  end

  sig { params(business: Business).void }
  def cancel(business)
    @business = T.let(business, T.nilable(Business))
    @subject = T.let("You've successfully cancelled your switch to metered billing", T.nilable(String))

    recipients = user_or_billing_recipients(@business)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: @subject
    )
  end

  sig { params(business: Business).void }
  def complete(business)
    @business = T.let(business, T.nilable(Business))
    @subject = T.let("Your account has successfully transitioned to metered billing", T.nilable(String))
    @usage_based_billing_docs_url = T.let(usage_based_billing_docs_url, T.nilable(String))
    @billing_licensing_link = T.let(billing_licensing_link, T.nilable(String))

    recipients = user_or_billing_recipients(@business)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: @subject
    )
  end

  private

  sig { returns(String) }
  def billing_licensing_link
    if @business&.billed_via_billing_platform?
      enterprise_billing_path(@business)
    else
      settings_billing_enterprise_url(@business)
    end
  end

  sig { returns(String) }
  def usage_based_billing_docs_url
    "https://docs.github.com/en/enterprise-cloud@latest/billing/managing-your-billing/about-usage-based-billing-for-licenses"
  end
end
