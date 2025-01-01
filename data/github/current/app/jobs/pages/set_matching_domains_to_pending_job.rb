# typed: true
# frozen_string_literal: true

# Internal: Finds page records that either match or are covered by another domain that has been
# recently verified and schedules them for further processing. This processing could include having protected
# domain records created for them and setting their status to pending.
module Pages
  class SetMatchingDomainsToPendingJob < ApplicationJob
    queue_as :pages_domain_protection

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    BATCH_SIZE = 5000

    def perform(protected_domain:)
      return unless should_continue_processing?(protected_domain)

      set_matching_domains_to_pending(protected_domain)
    end

    private

    def should_continue_processing?(protected_domain)
      protected_domain.present? && (protected_domain.verified? || protected_domain.pending?)
    end

    def set_matching_domains_to_pending(protected_domain)
      other_pages_on_domain(protected_domain) do |page|
        set_matching_domain_to_pending(page)
      end
    end

    def other_pages_on_domain(protected_domain)
      pages_enumerator = Page
        .with_domain_match(protected_domain.name, not_owner: protected_domain.owner)
        .in_batches(of: BATCH_SIZE)

      T.must(pages_enumerator).each do |batch_of_pages|
        batch_of_pages.each do |page|
          yield page
        end
      end
    end

    def set_matching_domain_to_pending(page)
      Pages::SetMatchingDomainToPendingJob.perform_later(owner: page.owner, domain_name: page.cname)
    end
  end
end
