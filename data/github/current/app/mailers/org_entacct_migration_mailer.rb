# typed: true
# frozen_string_literal: true

class OrgEntacctMigrationMailer < ApplicationMailer
  self.mailer_name = "mailers/org_entacct_migration"

  layout "layouts/primer_layout"
  LEARN_MORE_URL = T.let("#{GitHub.help_url}/admin/overview/about-enterprise-accounts#about-enterprise-accounts-on-github-enterprise-cloud", String)
  EA_FOR_ALL_URL = T.let("#{GitHub.blog_url}/2023-04-05-bring-your-enterprise-together-with-enterprise-accounts-for-all/", String)
  CHANGELOG_URL = T.let("#{GitHub.blog_url}/changelog/2024-06-19-upcoming-automatic-upgrade-to-the-enterprise-account-experience/", String)
  FAQ_URL = T.let("#{GitHub.help_url}/admin/overview/creating-an-enterprise-account#what-will-happen-after-i-upgrade-my-organization", String)

  def eligible(organization, upgrade_date)
    return unless organization.feature_flag_enabled?(:org_entacct_migration_mailer, default: false)
    return unless organization.eligible_for_upgrade_to_enterprise?

    emails = admin_emails(organization)
    return if emails.empty?

    @organization = organization
    @display_login = organization.display_login
    @upgrade_date = upgrade_date
    @learn_more_url = LEARN_MORE_URL
    @ea_for_all_url = EA_FOR_ALL_URL
    @changelog_url = CHANGELOG_URL
    @faq_url = FAQ_URL
    @upgrade_url = new_org_enterprise_upgrade_url(organization)

    premail(
      from: github_noreply,
      bcc: emails,
      subject: "[GitHub] Important: #{organization.display_login} will be upgraded to an enterprise account starting on #{upgrade_date}",
    )
  end

  def prompt_to_accept_corporate_tos(organization)
    return unless organization.feature_flag_enabled?(:org_entacct_migration_mailer, default: false)
    return unless organization.required_to_accept_corporate_tos?

    @organization = organization
    @display_login = organization.display_login
    emails = admin_emails(organization)
    return if emails.empty?

    premail(
      from: github_noreply,
      bcc: emails,
      subject: "[GitHub] Action required: switch to the GitHub Customer Agreement",
    )
  end
end
