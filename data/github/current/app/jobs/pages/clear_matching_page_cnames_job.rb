# typed: true
# frozen_string_literal: true

module Pages
  class ClearMatchingPageCnamesJob < ApplicationJob
    queue_as :pages_domain_protection

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    BATCH_SIZE = 5000

    def perform(protected_domain:)
      return unless domain_is_protected?(protected_domain)

      other_pages_on_domain(protected_domain) do |page|
        Pages::ClearMatchingPageCnameJob.perform_later(page: page, protected_domain: protected_domain)
      end
    end

    private

    def domain_is_protected?(protected_domain)
      protected_domain&.verified? || protected_domain&.pending?
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

  end
end
