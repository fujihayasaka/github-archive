# typed: true
# frozen_string_literal: true

class Actions::LargerRunnersNonUsageMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/larger_runners"

  layout "layouts/primer_layout_minimal"

  def disable_public_ip_and_email(entity, expiration_days, runner_names)
    @entity = entity
    @subject = "Change to GitHub Action Runner Public IP ranges"
    @expiration_days = expiration_days
    @runner_names = runner_names
    @setting_link_content = settings_link_and_wording

    premail(
      from: github_noreply,
      bcc: admin_emails(entity),
      subject: @subject
    )
  end

  def settings_link_and_wording
    case @entity
    when Organization
      {
        link: settings_org_actions_runners_url(@entity),
        text: @entity.name
      }
    when Business
      {
        link: settings_actions_runners_enterprise_url(@entity),
        text: @entity.slug
      }
    end
  end
end
