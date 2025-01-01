# typed: true
# frozen_string_literal: true

# Internal: When a user/organization gets deleted, all the domains protected irrespective of its state gets deleted as well
module Pages
  class DeleteProtectedDomainsJob < ApplicationJob
    queue_as :pages_domain_protection
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    BATCH_SIZE = 5000

    def perform(owner_id:)
      # Basic telemetry
      Failbot.push(app: "pages")

      log_context(owner_id) do
        protected_domains = Page::ProtectedDomain.where(owner_id: owner_id).includes(:owner)

        protected_domains.each do |domain|
          with_write { domain.destroy }
          GitHub.logger.info("Owner deletion issued", {
            "gh.user.id" => owner_id,
            "gh.pages.protected_domain.id" => domain.id,
          })
          GitHub.dogstats.increment "pages.protected_domain.job.owner_deleted"
        end
      end
    end

    def log_context(owner_id, &blk)
      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "delete_protected_domains_job",
        "gh.catalog_service" => "github/pages",
        "gh.user.id" => owner_id,
        &blk
      )
    end
  end
end
