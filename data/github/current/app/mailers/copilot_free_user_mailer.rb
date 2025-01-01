# typed: strict
# frozen_string_literal: true

class CopilotFreeUserMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  extend T::Sig

  self.mailer_name = "mailers/copilot_free_user"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(user: User, expiration: Time).returns(String) }
  def expiration_warning(user, expiration)
    @user = T.let(user, T.nilable(User))
    @expiration = T.let(expiration, T.nilable(Time))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your free GitHub Copilot access is ending soon",
    )
  end

  sig { params(user: User).returns(String) }
  def expired(user)
    @user = T.let(user, T.nilable(User))
    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Your free GitHub Copilot access has expired",
    )
  end

  sig { params(user: User, next_check_at: Date, coupon_expires_at: T.nilable(Date)).returns(String) }
  def refreshed(user, next_check_at, coupon_expires_at = nil)
    @user = T.let(user, T.nilable(User))
    @next_check_at = T.let(next_check_at, T.nilable(Date))
    @coupon_expires_at = T.let(coupon_expires_at, T.nilable(Date))

    # Don't include the coupon expiry date if it's after the next scheduled check
    if coupon_expires_at && (coupon_expires_at > next_check_at)
      @coupon_expires_at = nil
    end

    subject = if @coupon_expires_at
      "Your GitHub Copilot access will expire soon"
    else
      "Your GitHub Copilot access has been renewed"
    end

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: subject,
    )
  end

  sig { params(user: User).returns(String) }
  def paid_user_became_free(user)
    @user = T.let(user, T.nilable(User))
    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "Accessing your free Copilot subscription",
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    @user
  end
end
