# typed: true
# frozen_string_literal: true
class MigrationsMailer < ApplicationMailer
  extend T::Sig

  self.mailer_name = "mailers/migrations"

  helper :application

  layout "layouts/primer_layout"

  # Sends an email alert to GitHub Enterprise Importer users about IP changes being announced in August 2023
  sig { params(user: User).returns(T.untyped) }
  def ip_addresses_update_2023_08(user)
    premail(
      to: user_email(user),
      subject: "[GitHub] IP allowlisting changes for GitHub Enterprise Importer"
    )
  end

  # Sends an email alert to GitHub Enterprise Importer users about IP changes being announced in October 2023
  sig { params(user: User).returns(T.untyped) }
  def ip_addresses_update_2023_10(user)
    premail(
      to: user_email(user),
      subject: "[GitHub] Update your IP allow lists for GitHub Enterprise Importer"
    )
  end

  # Sends an email alert to GitHub Enterprise Importer users about IP changes being announced in October 2023,
  # correcting an earlier email
  sig { params(user: User).returns(T.untyped) }
  def ip_addresses_update_2023_10_correction(user)
    premail(
      to: user_email(user),
      subject: "CORRECTION: Update your IP allow lists for GitHub Enterprise Importer"
    )
  end

  # Sends an email alert to Source Imports REST API users about the API's deprecation, announced in October 2023
  sig { params(user: User).returns(T.untyped) }
  def source_imports_api_deprecation_2023_10(user)
    premail(
      to: user_email(user),
      subject: "Ending support for GitHub's Source Imports REST API"
    )
  end
end
