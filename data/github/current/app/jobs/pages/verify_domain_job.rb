# typed: true
# frozen_string_literal: true

# Internal: Perform a verification of a ProtectedDomain object by asking it to verify itself. This is used by
# PagesVerifyDomainsJob in order to help parallelize the workload.
module Pages
  class VerifyDomainJob < ApplicationJob
    class PagesDnsTxtRecordError < StandardError; end

    queue_as :pages_domain_protection

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on PagesDnsTxtRecordError, attempts: 6, wait: 5.minutes

    # Internal: Perform a verification of a ProtectedDomain object by asking it to verify itself.
    #
    # protected_domain - The ProtectedDomain object to verify.
    def perform(protected_domain:)
      return if GitHub.enterprise?

      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "verify_domain_job",
        "gh.catalog_service" => "github/pages") do

        result = verify_domain(protected_domain)

        raise PagesDnsTxtRecordError unless result == true
      end
    end

    private

    def verify_domain(protected_domain)
      if !GitHub.enterprise?
        result = with_write { protected_domain.verify }
        GitHub.dogstats.increment "pages.protected_domain.job.verify",
                     tags: ["verify_state:#{result}"]
        if protected_domain.saved_change_to_state?(to: "pending")
          PagesMailer.domain_pending_unverification(protected_domain).deliver_later
        end

        result
      else
        true
      end
    end
  end
end
