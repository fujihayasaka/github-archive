# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Pages
  class ClearMatchingPageCnameJob < ApplicationJob
    queue_as :pages_domain_protection

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(page:, protected_domain:)
      owner = page.owner
      domain_names = [page.cname, Page::ProtectedDomain.parent_domain_of(page.cname)].compact
      protected_by_owner = page_domain_is_protected_by_owner?(domain_names, owner)
      not_protected_by_other = !page_domain_is_protected_by_other?(domain_names, owner)

      GitHub.logger.info(
        "Clearing page custom domain",
        "gh.protected_domain.name" => protected_domain.name,
        "gh.protected_domain.owner.id" => protected_domain.owner_id,
        "gh.page.id" => page.id,
        "gh.page.cname" => page.cname,
        "gh.page.owner.id" => owner.id,
        "result" =>
          if protected_by_owner
            "ignored (domain protected by page owner)"
          elsif not_protected_by_other
            "ignored (domain not protected by other)"
          else
            "cleared"
          end,
      )

      return if protected_by_owner || not_protected_by_other

      GitHub.dogstats.increment "pages.protected_domain.job.clear_matching_page_cname"
      with_write do
        page.disassociate_domains
      end
      PagesMailer.domain_disassociated(page.cname, owner, [page.repository.name_with_display_owner]).deliver_later unless owner.spammy?
    end

    private

    def page_domain_is_protected_by_owner?(domain_names, owner)
      Page::ProtectedDomain.where(state: %w[verified pending], name: domain_names, owner: owner).exists?
    end

    def page_domain_is_protected_by_other?(domain_names, owner)
      Page::ProtectedDomain.where(state: %w[verified pending], name: domain_names).where.not(owner: owner).exists?
    end

  end
end
