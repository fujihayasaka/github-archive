# typed: true
# frozen_string_literal: true

# Internal: Scans the list of previously verified protected domains and ensures that they still
# have valid DNS TXT records. Does not run in enterprise mode.
module Pages
  class VerifyDomainsJob < ApplicationJob
    queue_as :pages_domain_protection

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit

    BATCH_SIZE = 5000

    # Internal: Scans the list of previously verified protected domains and ensures that they still
    # have valid DNS TXT records. Does not run in enterprise mode.
    def perform
      return if GitHub.enterprise?

      GitHub.logger.info(
        "code.function" => "perform",
        "code.namespace" => self.class.name,
        "gh.catalog_service" => "github/pages")
      find_domains_to_verify_in_batches.each { |domains| verify_domains(domains) }
    end

    private

    def find_domains_to_verify_in_batches
      # Note: Check #for_verification_scan for the limited set of attributes that are returned.
      Page::ProtectedDomain.for_verification_scan.in_batches(of: BATCH_SIZE)
    end

    def verify_domains(domains)
      domains.each { |domain| verify_domain(domain) }
    end

    def verify_domain(protected_domain)
      Pages::VerifyDomainJob.perform_later(protected_domain: protected_domain)
    end
  end
end
