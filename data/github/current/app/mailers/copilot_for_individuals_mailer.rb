# typed: strict
# frozen_string_literal: true

class CopilotForIndividualsMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_for_individuals"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(user: User, billing_product: Billing::ProductUUID, payment_type: T.nilable(String), free_trial_ends_on: T.any(Time, Date, DateTime), days_left_in_trial: Integer).returns(String) }
  def scheduled_payment_reminder(user, billing_product, payment_type, free_trial_ends_on, days_left_in_trial)
    @user = T.let(user, T.nilable(User))
    @bill = T.let(user_friendly_bill_amount(T.must(billing_product.charges.first)), T.nilable(String))
    @billing_method = T.let(user_friendly_payment_type(payment_type), T.nilable(String))
    @free_trial_ends_on = T.let(free_trial_ends_on.strftime("%B %-d"), T.nilable(String))
    @settings_user_billing_path = T.let(settings_user_billing_url, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your GitHub Copilot trial ends in #{days_left_in_trial} days",
    )
  end

  sig { params(user: User, billing_product: Billing::ProductUUID, payment_type: T.nilable(String), free_trial_ends_on: T.any(Time, Date, DateTime)).returns(String) }
  def one_day_from_scheduled_payment(user, billing_product, payment_type, free_trial_ends_on)
    @user = T.let(user, T.nilable(User))
    @bill = T.let(user_friendly_bill_amount(T.must(billing_product.charges.first)), T.nilable(String))
    @billing_method = T.let(user_friendly_payment_type(payment_type), T.nilable(String))
    @free_trial_ends_on = T.let(free_trial_ends_on.strftime("%B %-d"), T.nilable(String))
    @settings_user_billing_path = T.let(settings_user_billing_url, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your GitHub Copilot trial ends tomorrow",
    )
  end

  sig { params(user: User, free_trial_ends_on: T.any(Time, Date, DateTime)).returns(String) }
  def cancellation_reminder(user, free_trial_ends_on)
    @user = T.let(user, T.nilable(User))
    @free_trial_ends_on = T.let(free_trial_ends_on.strftime("%B %-d"), T.nilable(String))
    @settings_user_billing_path = T.let(settings_user_billing_url, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your GitHub Copilot trial ends in 7 days",
    )
  end

  sig { params(user: User).returns(String) }
  def one_day_from_cancellation(user)
    @user = T.let(user, T.nilable(User))
    @settings_user_billing_path = T.let(settings_user_billing_url, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your GitHub Copilot trial ends tomorrow",
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    @user
  end

  private

  sig { params(charge: Billing::ProductUUID::Charge).returns(String) }
  def user_friendly_bill_amount(charge)
    "$#{charge.price.to_i}/#{charge.billing_duration}"
  end

  sig { params(payment_type: T.nilable(String)).returns(String) }
  def user_friendly_payment_type(payment_type)
    payment_type == "paypal" ? "PayPal account" : "credit card"
  end
end
