# typed: true
# frozen_string_literal: true

# Internal: Scans the list of protected domains in the pending status and ensures that they
# have valid DNS TXT records. Does not run in enterprise mode.
module Pages
  class ProcessPendingDomainsJob < ApplicationJob
    queue_as :pages_domain_protection

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit

    BATCH_SIZE = 5000

    # Internal: Scans the list of previously verified protected domains and ensures that they still
    # have valid DNS TXT records. Does not run in enterprise mode.
    def perform
      return if GitHub.enterprise?

      log_context do
        find_domains_to_verify_in_batches.each { |domains| process_domains(domains) }
      end
    end

    private

    def log_context(&block)
      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "process_pending_domains_job",
        "gh.catalog_service" => "github/pages",
        &block
      )
    end

    def find_domains_to_verify_in_batches
      # Note: Check #for_pending_verification_scan for the limited set of attributes that are returned.
      Page::ProtectedDomain.for_pending_verification_scan.in_batches(of: BATCH_SIZE)
    end

    def process_domains(domains)
      domains.each { |domain| process_domain(domain) }
    end

    def process_domain(protected_domain)
      Pages::ProcessPendingDomainJob.perform_later(protected_domain: protected_domain)
    end
  end
end
