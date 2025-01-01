# typed: true
# frozen_string_literal: true

# Internal: Perform a verification of a ProtectedDomain object in the pending state by asking it to process itself.
# This is used by ProcessPendingDomainsJob in order to help parallelize the workload.
module Pages
  class ProcessPendingDomainJob < ApplicationJob
    class ProcessPendingError < StandardError; end

    queue_as :pages_domain_protection

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on ProcessPendingError, attempts: 6, wait: 5.minutes

    # Internal: Perform a verification of a ProtectedDomain object in the pending state by asking it to process itself.
    #
    # protected_domain - The ProtectedDomain object to verify.
    def perform(protected_domain:)
      return if GitHub.enterprise?

      log_context(protected_domain) do
        result = process_pending(protected_domain)
        raise ProcessPendingError unless result == true
      end
    end

    private

    def log_context(protected_domain, &block)
      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "process_pending_domain_job",
        "gh.catalog_service" => "github/pages",
        "gh.pages.protected_domain.id" => protected_domain.id,
        "gh.pages.protected_domain" => protected_domain.name,
        "gh.pages.protected_domain.unverified_at" => protected_domain.unverified_at,
        &block
      )
    end

    def process_pending(protected_domain)
      result = with_write { protected_domain.verify }
      GitHub.dogstats.increment "pages.protected_domain.job.process_pending",
                  tags: ["verify_state:#{result}"]

      GitHub.logger.info("gh.pages.result" => result)
      if protected_domain.saved_change_to_state?(to: "unverified")
        PagesMailer.domain_unverified(protected_domain).deliver_later
        if Page::ProtectedDomain.protected?(protected_domain.name, protected_domain.parent_domain)
          Pages::DeleteProtectedDomainJob.perform_later(domain_name: protected_domain.name, owner: protected_domain.owner)
        end
      end

      result
    end
  end
end
