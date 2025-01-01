# typed: true
# frozen_string_literal: true

class ExemptionRequestMailer < ApplicationMailer
  extend T::Sig

  self.mailer_name = "mailers/exemption_request"

  layout "layouts/primer_layout"

  sig do
    params(
      bypasser: User,
      request: Exemptions::ExemptionRequest,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def push_bypass(bypasser, request, subject, reason, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(bypasser, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
      response: Exemptions::ExemptionResponse,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def request_status_changed(request, response, subject, reason, permalink)
    @request = request
    @response = response
    @status = response.status == "rejected" ? "denied" : response.status
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  private

  def default_footer_links
    [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]
  end
end
