# typed: true
# frozen_string_literal: true

class PlanningTrackingBetaMailer < ApplicationMailer
  self.mailer_name = "mailers/planning_tracking_beta"

  layout "layouts/primer_layout"

  SUBJECT = "Welcome %{org_name} to the GitHub Issues: Sub-issues, issue types and advanced search beta"

  sig { params(organization: Organization, user: User).returns(String) }
  def waitlist_acceptance(organization, user)
    @organization = organization
    @organization_url = URI.join(GitHub.url.to_s, @organization.display_login).to_s

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: SUBJECT % { org_name: organization.safe_profile_name },
    )
  end
end
