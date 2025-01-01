# typed: strict
# frozen_string_literal: true

class CopilotLimitedUserMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_limited_user"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(user: User).returns(String) }
  def subscribe(user)
    @user = T.let(user, T.nilable(User))
    @header = T.let("How to get started with GitHub Copilot.", T.nilable(String))
    @banner_img = T.let("images/email/copilot/free-banner.png", T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "GitHub Copilot: What’s in your free plan 🤖",
    )
  end

  sig { returns(T.nilable(::User)) }
  def mailable
    @user
  end
end
