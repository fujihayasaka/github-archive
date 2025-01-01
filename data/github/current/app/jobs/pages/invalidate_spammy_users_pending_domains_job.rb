# typed: true
# frozen_string_literal: true

# Sets a spammy user's protected domains to "unverified" if they are in a "pending" state
module Pages
  class InvalidateSpammyUsersPendingDomainsJob < ApplicationJob
    queue_as :pages_domain_protection

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(owner)
      if owner.spammy?
        Page::ProtectedDomain.where(owner: owner, state: "pending", last_verified_at: nil).in_batches(of: 1000) do |batch|
          domains_to_revoke = batch.map(&:name)

          with_write do
            batch.update_all(state: "unverified", unverified_at: nil)
            domains_to_revoke.each do |domain_name|
              Pages::DeleteProtectedDomainJob.perform_later(owner: owner, domain_name: domain_name)
            end
          end
        end
      end
    end
  end
end
