# typed: true
# frozen_string_literal: true

class PorterMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/porter"

  def import_success(options)
    extract_options(options)

    mail(
      to: recipient_email,
      subject: "Import to #{@repository_name} is finished!",
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
    @user            = options.fetch(:current_user)
    repository       = options.fetch(:repository)
    @repository_name = repository.name_with_display_owner
    @owner           = repository.owner
    @import_url      = "#{repository.permalink}/import"
    @author_url      = "#{repository.permalink}/import/authors"
    @authors_found   = options.fetch(:authors_found) { false }
  end
end
