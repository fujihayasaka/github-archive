# typed: true
# frozen_string_literal: true

class HookMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/hook"

  def stafftools_disable_notice(hook)
    @hook = hook
    recipients = user_or_admin_recipients(owner(hook))

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Webhook disabled for #{hook.owner_name_and_type}",
    )
  end

  def stafftools_enable_notice(hook)
    @hook = hook
    recipients = user_or_admin_recipients(owner(hook))

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Webhook enabled for #{hook.owner_name_and_type}",
    )
  end

  def oauth_hook_stafftools_disable_notice(hook)
    @hook = hook
    @oauth_app = hook.oauth_application
    recipients = user_or_admin_recipients(@oauth_app.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Webhook disabled for #{hook.owner_name_and_type}",
    )
  end

  def oauth_hook_stafftools_enable_notice(hook)
    @hook = hook
    @oauth_app = hook.oauth_application
    recipients = user_or_admin_recipients(@oauth_app.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Webhook enabled for #{hook.owner_name_and_type}",
    )
  end

  private

  def owner(hook)
    return hook.installation_target if hook.hook_type == :org || hook.hook_type == :business
    hook.installation_target.owner
  end
end
