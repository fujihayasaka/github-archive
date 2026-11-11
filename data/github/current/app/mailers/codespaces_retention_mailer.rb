# typed: true
# frozen_string_literal: true

class CodespacesRetentionMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/codespaces_retention"

  layout "layouts/primer_layout"

  def retention_warning_batch(codespaces)
    # navigate to http://github.localhost/rails/mailers/codespaces_retention/retention_warning_batch?part=text%2Fhtml
    # to preview this mailer
    @codespaces = codespaces
    return unless codespaces.pluck(:owner_id).uniq.size == 1

    premail(
      from: github_noreply,
      to: user_email(codespaces.first.owner),
      subject: "You have codespaces that are about to be deleted",
    )
  end
end
