# typed: true
# frozen_string_literal: true

# Internal: Finds or creates protected domain records that either match or are covered by another domain that has been
# recently verified and sets their status to pending if needed.
module Pages
  class SetMatchingDomainToPendingJob < ApplicationJob
    queue_as :pages_domain_protection

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(owner:, domain_name:)
      log_context do
        protected_domain = find_or_build_protected_domain(owner, domain_name)
        return unless should_continue_processing?(protected_domain)

        set_protected_domain_to_pending(protected_domain)
      end
    end

    private

    def find_or_build_protected_domain(owner, domain_name)
      # https://thehub.github.com/engineering/development-and-ops/dotcom/testing/linting/find-or-create/
      find_domain(owner, domain_name) || new_domain(owner, domain_name)
    end

    def new_domain(owner, domain_name)
      stripped_domain_name = domain_name.gsub(/\Awww\./i, "")
      new_domain = Page::ProtectedDomain.new(owner: owner, name: stripped_domain_name)
      GitHub.dogstats.increment "pages.protected_domain.job.new_domain",
                    tags: ["owner_type:#{owner.type}, state:#{new_domain.state}"]
      new_domain
    end

    def find_domain(owner, domain_name)
      Page::ProtectedDomain.find_by(owner: owner, name: domain_name)
    end

    def should_continue_processing?(protected_domain)
      !(protected_domain.verified? || protected_domain.pending?)
    end

    def set_protected_domain_to_pending(protected_domain)
      if !protected_domain.owner.spammy?
        with_write { protected_domain.pending! }
        PagesMailer.existing_domain_pending_unverification(protected_domain).deliver_later
        GitHub.dogstats.increment "pages.protected_domain.job.set_to_pending"
      end
    end

    def log_context(&block)
      GitHub.logger.with_named_tags(
        "code.function" => "perform",
        "code.namespace" => "set_matching_domain_to_pending_job",
        "gh.catalog_service" => "github/pages",
        &block)
    end
  end
end
