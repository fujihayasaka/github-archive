# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# RestoreSoftDeletedPagesJob restores a page when under an organization when
# the visibility/billing is changed but they still have access to the page.
class RestoreSoftDeletedPagesJob < ApplicationJob
  queue_as :pages_soft_delete_restore

  class RestoreSoftDeletedPagesError < RuntimeError
    attr_reader :organization_id, :page_ids

    def initialize(message, organization_id: nil, page_ids: nil)
      super(message)
      @organization_id = organization_id
      @page_ids = page_ids
    end
  end

  REPO_BATCH_SIZE = 10_000
  PAGE_BATCH_SIZE = 1_000

  retry_on RestoreSoftDeletedPagesError, wait: 2.seconds, attempts: 3 do |_job, error|
    Failbot.report(
      error, {
      "gh.org.id" => error.organization_id,
      "gh.pages.id" =>   error.page_ids
    })
    GitHub.dogstats.increment("pages.soft_delete.restore", tags: ["state:failed"])
  end

  def perform(organization)
    restore_pages(organization)
  end

  def restore_pages(organization)
    failed_restored_pages = T.let([], T::Array[Integer])
    allows_private_pages = organization.plan_supports_private_pages?
    allows_pages_for_private_repos = organization.plan_supports?(:pages, visibility: :private)

    Repositories.domain.repo_ids_by_owners(owner_ids: [organization.id], unlocked_only: true, active_only: true) do |repo_ids|
      batch = Page.where.not(deleted_at: nil).where(repository_id: repo_ids.to_a)
      failed_restored_pages += process_batch(batch, organization, allows_private_pages, allows_pages_for_private_repos)
    end

    if failed_restored_pages.any?
      raise RestoreSoftDeletedPagesError.new(
        message: "failed to restore soft deleted pages.",
        organization_id: organization.id,
        page_ids: failed_restored_pages
      )
    else
      GitHub.dogstats.increment("pages.soft_delete.restore", tags: ["state:succeed"])
    end
  end

  def process_batch(batch, organization, allows_private_pages, allows_pages_for_private_repos)
    failed_restored_pages = []

    batch.each do |page|
      begin
        with_write do
          Repository.throttle do
            if allows_private_pages && page.private?
              page.restore_deleted
            elsif allows_pages_for_private_repos && page.public?
              page.restore_deleted
            end
          end
        end
      rescue RuntimeError
        failed_restored_pages.push(page.id)
        Failbot.report(RuntimeError.new("failed to restore soft deleted page."), {
          "gh.org.id" => organization.id,
          "gh.pages.id" => page.id
          })
      end
    end

    failed_restored_pages
  end

  retry_on_recoverable_exceptions
  retry_on_dirty_exit
end
