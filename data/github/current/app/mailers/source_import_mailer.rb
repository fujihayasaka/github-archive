# typed: true
# frozen_string_literal: true

class SourceImportMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/source_import"

  def import_success(options)
    extract_options(options)

    mail(
      to: recipient_email,
      subject: "Import to #{@repository_name} has finished!",
    )
  end

  def import_failure(options)
    extract_options(options)

    mail(
      to: recipient_email,
      subject: "Import to #{@repository_name} failed",
    )
  end

  private

  def recipient_email
    user_email(@user, GitHub.newsies.email(@user, @owner).value)
  end

  def extract_options(options)
    @user            = options.fetch(:user)
    repository       = options.fetch(:repository)
    @status          = options.fetch(:status)
    @failure_reason  = options.fetch(:failure_reason)
    @error_details   = options.fetch(:error_details, [])
    @repository_name = repository.name_with_display_owner
    @owner           = repository.owner
  end
end
