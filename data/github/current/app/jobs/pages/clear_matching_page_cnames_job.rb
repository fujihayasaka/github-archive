# rubocop:todo GitHub/EnforcePackageAppStructure
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
      Page
        .with_domain_match(protected_domain.name)
        .in_batches(of: BATCH_SIZE)
        .each do |batch_of_pages|

        repo_ids = Repositories.domain.repo_ids_excluding_owners(
          excluded_owner_ids: [protected_domain.owner.id],
          repo_ids: batch_of_pages.pluck(:repository_id)
        )

        batch_of_pages.select { |p| repo_ids.include?(p.repository_id) }.each do |page|
          yield page
        end
      end
    end

  end
end
