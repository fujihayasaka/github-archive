# typed: true
# frozen_string_literal: true

class BusinessStartupsApplicationMailer < ApplicationMailer
  include GitHub::Memoizer
  self.mailer_name = "mailers/business_startups_application"

  layout "layouts/primer_layout_minimal"

  sig { params(application: BusinessStartupsProgram).void }
  def acceptance_email(application)
    @application = application
    @applicant_name = application.application_data&.dig("first_name") || "there"
    @company_name = application.application_data&.dig("company_name") || "your company"
    @business_name = application.business&.name || @company_name
    @business_slug = application.business&.slug
    @credit_expiry_date = (application.accepted_at || Time.current).advance(years: 1).strftime("%B %d, %Y")

    recipient = application.applicant_email
    return unless recipient.present?

    GitHub.dogstats.increment("mailer.business_startups_application.acceptance_email.count")

    premail(
      to: recipient,
      subject: "Welcome to GitHub for Startups!",
      template_name: "acceptance_email",
    )
  end

  sig { params(application: BusinessStartupsProgram).void }
  def rejection_email(application)
    @application = application
    @applicant_name = application.application_data&.dig("first_name") || "there"
    @company_name = application.application_data&.dig("company_name") || "your company"
    @rejection_reason = application.rejection_reason

    recipient = application.applicant_email
    return unless recipient.present?

    GitHub.dogstats.increment("mailer.business_startups_application.rejection_email.count")

    premail(
      to: recipient,
      subject: "[GitHub for Startups] - Application update",
      template_name: "rejection_email",
    )
  end

  sig { params(application: BusinessStartupsProgram).void }
  def graduation_email(application)
    @application = application
    @applicant_name = application.application_data&.dig("first_name") || "there"
    @company_name = application.application_data&.dig("company_name") || "your company"
    @business_name = application.business&.name || @company_name
    @business_slug = application.business&.slug

    recipient = application.applicant_email
    return unless recipient.present?

    GitHub.dogstats.increment("mailer.business_startups_application.graduation_email.count")

    premail(
      to: recipient,
      subject: "[GitHub for Startups] - Program completion",
      template_name: "graduation_email",
    )
  end
end
