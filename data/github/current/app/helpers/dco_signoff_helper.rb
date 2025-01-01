# typed: true
# frozen_string_literal: true

module DcoSignoffHelper
  extend self

  # Returns the DCO sign-off text containing user name and public email.
  def dco_signoff_text(user, params = nil)
    author_name, author_email = User.git_author_info(user)

    # In case user chose different public email while submitting the form.
    author_email = params[:author_email] if params.present? && params[:author_email].present?

    "Signed-off-by: #{author_name} <#{author_email}>"
  end

  def dco_signoff_help_url
    "https://docs.github.com/organizations/managing-organization-settings/managing-the-commit-signoff-policy-for-your-organization"
  end
end
