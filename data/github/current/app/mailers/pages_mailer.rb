# typed: true
# frozen_string_literal: true

class PagesMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/pages"

  layout "layouts/primer_layout",
    only: [:domain_pending_unverification, :existing_domain_pending_unverification, :domain_unverified, :domain_disassociated]

  def build_failure(pusher, repository, error, build = nil)
    # Ignore the email if the build was initiated by a staff
    return if staff_build?(pusher)

    # Ignore the email if the pusher cannot pull the repository anymore
    # Emails can remain in the queue for a bit so this check is helpful. Pages sites building with
    # deploy keys also tend to send emails to pushers associated with the deploy key who may not have access to the
    # repository anymore.
    return unless repository.pullable_by?(pusher)

    # Ignore the email if the build ran in Actions (we cannot cheaply differientiate between failed/cancelled jobs)
    # Actions sends emails already for failed workflows.
    return if repository&.page&.dynamic_workflow_enabled?

    @error = error
    @build = build
    @repository = repository
    mail(
      from: github,
      to: recipient_email(pusher, repository),
      subject: "[#{repository.name_with_display_owner}] Page build failure",
      message_id: "<#{repository.name_with_display_owner}/page-#{message_id_suffix build}@#{GitHub.host_name}>",
    )
  end

  def build_warning(pusher, repository, warning, build = nil)
    return if staff_build?(pusher)
    @warning = warning
    @build = build
    @repository = repository
    mail(
      from: github,
      to: recipient_email(pusher, repository),
      subject: "[#{repository.name_with_display_owner}] Page build warning",
      message_id: "<#{repository.name_with_display_owner}/page_warning-#{message_id_suffix build}@#{GitHub.host_name}>",
    )
  end

  def domain_pending_unverification(domain)
    @domain = domain
    @pages_settings_url = pages_settings_url(domain.owner)
    @protected_domain_url = protected_domain_url(domain)
    premail(
      from: github,
      bcc: recipients(domain.owner),
      subject: "[#{domain.owner.name}] Please verify your Pages domain (ACTION NEEDED)",
    )

    GitHub.dogstats.increment "pages.protected_domain.mailer.pending_to_unverified"
  end

  def existing_domain_pending_unverification(domain)
    @domain = domain
    @pages_settings_url = pages_settings_url(domain.owner)
    @protected_domain_url = protected_domain_url(domain)
    premail(
      from: github,
      bcc: recipients(domain.owner),
      subject: "[#{domain.owner.name}] Please verify your Pages domain (ACTION NEEDED)",
    )

    GitHub.dogstats.increment "pages.protected_domain.mailer.existing_pending_to_unverified"
  end

  def domain_unverified(domain)
    @domain = domain
    @pages_settings_url = pages_settings_url(domain.owner)
    premail(
      from: github,
      bcc: recipients(domain.owner),
      subject: "[#{domain.owner.name}] Your Pages domain has been unverified",
    )
    GitHub.dogstats.increment "pages.protected_domain.mailer.unverified"
  end

  def domain_disassociated(domain_name, owner, repositories)
    @domain_name = domain_name
    @repositories = repositories
    @pages_settings_url = pages_settings_url(owner)
    @owner_name = owner
    premail(
      from: github,
      bcc: recipients(owner),
      subject: "[#{owner.name}] Your Pages custom domain has been removed",
    )
    GitHub.dogstats.increment "pages.protected_domain.mailer.disassociated"
  end

  private

  def recipients(owner)
    # an organization's #admins method returns an activerecord relation, but a
    # user's #admins method returns an array (of self). So admins.map(&:email)
    # is an N+1 query when it belongs to an org, but `includes` or `preloads`
    # can't be called on an array. Hence the conditional.
    if owner.organization?
      owner.admins.includes(:primary_user_email).map(&:primary_user_email)
    else
      owner.admins.map(&:email)
    end
  end

  def pages_settings_url(owner)
    if owner.organization?
      settings_org_pages_url(owner)
    else
      settings_pages_url
    end
  end

  def protected_domain_url(domain)
    if domain.owner.organization?
      settings_org_pages_protected_domain_url(domain.owner.name, domain.name)
    else
      settings_pages_protected_domain_url(domain.name)
    end
  end

  def message_id_suffix(build)
    if build
      build.id
    else
      "0-#{Time.now.to_i}"
    end
  end

  def recipient_email(pusher, repository)
    user_email(pusher, GitHub.newsies.email(pusher, repository.owner).value)
  end

  # Is the build is a staff-initiated build (e.g., via stafftools)?
  def staff_build?(pusher)
    GitHub.guard_audit_log_staff_actor? && (User.staff_user == pusher)
  end
end
