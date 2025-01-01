# typed: true
# frozen_string_literal: true

class LargerRunnersAccountIpDisableMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/larger_runners"

  layout "layouts/primer_layout_minimal"

  # Email Organization billing manager(s).
  # Notify them that their Public IP Range(s) have been disabled for Organization Larger Runners
  # Provide affected pool names.
  def public_ip_change_for_org(account, affected_pool_names)
    @account = account
    @affected_pools = affected_pool_names
    @subject = "Changes to your Public IP Ranges for GitHub Actions Runners"
    @upgrade_link = settings_org_billing_url(account)

    premail(
      from: github_noreply,
      to: billing_emails(@account),
      subject: @subject
    )
  end

  # Email Enterprise billing manager(s).
  # Notify them that their Public IP Range(s) have been disabled for Enterprise Larger Runners.
  # Notify them of any affected member Organizations.
  # Provide Enterprise level affected pool names, as well affected Organization names.
  def public_ip_change_for_enterprise(account, affected_enterprise_pool_names, affected_member_org_names)
    @account = account
    @affected_enterprise_pools = affected_enterprise_pool_names
    @affected_member_orgs = affected_member_org_names
    @subject = "Changes to your Public IP Ranges for GitHub Actions Runners"
    @upgrade_link = settings_billing_enterprise_url(account)

    premail(
      from: github_noreply,
      to: billing_emails(@account),
      subject: @subject
    )
  end
end
