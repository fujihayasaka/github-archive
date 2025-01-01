# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Internal: When a user/organization deletes a domain protection, go through all Pages sites
# covered by the domain protection and remove the custom domain association if needed.
module Pages
  class DeleteProtectedDomainJob < ApplicationJob
    queue_as :pages_domain_protection
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    BATCH_SIZE = 5000

    def perform(domain_name:, owner:)
      # Basic telemetry
      Failbot.push(app: "pages")

      log_context(domain_name) do
        # If the domain protection is still there, ignore
        return if domain_protection_exists?(domain_name, owner)

        other_pages_on_domain(domain_name).in_batches(of: BATCH_SIZE).each do |batch_of_pages|
          repo_ids = Repositories.domain.repo_ids_by_owner(
            owner_id: owner.id,
            repo_ids_in: batch_of_pages.pluck(:repository_id),
            public_only: false
          )
          process_batch_of_pages(batch_of_pages.select { |p| repo_ids.include?(p.repository_id) }, owner, domain_name)
        end
      end
    end

    private

    def process_batch_of_pages(batch_of_pages, owner, domain_name)
      affected_domain_names = batch_of_pages.pluck(:cname, :parent_domain).flatten.uniq.compact
      protected_domain_names_by_others = other_protected_domain_names(owner, affected_domain_names)

      to_possibly_unpublish = batch_of_pages.select do |page|
        protected_domain_names_by_others.include?(page.cname) || protected_domain_names_by_others.include?(page.parent_domain) || protected_domain_names_by_others.include?(page.www_parent_domain)
      end

      return if to_possibly_unpublish.blank?

      domain_names = to_possibly_unpublish.pluck(:cname, :parent_domain).flatten.compact.uniq
      protected_domain_names = owners_protected_domain_names(owner, domain_names)

      to_keep, to_unpublish = to_possibly_unpublish.partition do |page|
        protected_domain_names.include?(page.cname) || protected_domain_names.include?(page.parent_domain) || protected_domain_names.include?(page.www_parent_domain)
      end

      return if to_unpublish.blank?

      GitHub.logger.info({
        "gh.pages.protected_domain.unpublished" => to_unpublish.map(&:id),
        "gh.pages.protected_domain.kept_published" => to_keep.map(&:id),
      })

      Page.where(id: to_unpublish.pluck(:id)).each do |page|
        with_write { page.disassociate_domains }
        GitHub.dogstats.increment "pages.protected_domain.job.disassociate_domain"
      end
      to_unpublish_names = to_unpublish.map { |page| page.repository.nwo }
      PagesMailer.domain_disassociated(domain_name, owner, to_unpublish_names).deliver_later unless owner.spammy?
    end

    def domain_protection_exists?(name, owner)
      Page::ProtectedDomain.where(name: name, owner: owner, state: %w[verified pending]).exists?
    end

    def other_protected_domain_names(owner, domain_names)
      Page::ProtectedDomain.where(state: %w[verified pending], name: domain_names).where.not(owner: owner).pluck(:name)
    end

    def owners_protected_domain_names(owner, domain_names)
      Page::ProtectedDomain.where(state: %w[verified pending], name: domain_names, owner: owner).pluck(:name)
    end

    def other_pages_on_domain(domain_name)
      Page.select("pages.*").with_domain_match(domain_name)
    end

    def log_context(domain_name, &blk)
      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "pages-delete-protected-domain-job",
        "gh.catalog_service" => "github/pages",
        "gh.pages.domain" => domain_name,
        &blk
      )
    end

  end
end
