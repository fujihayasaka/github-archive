# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DestroyPrivatePageJob destroy private pages under an organization when billing downgrade plan from business plus.
class DestroyPrivatePageJob < ApplicationJob
  queue_as :background_destroy

  class DestroyPrivatePageError < RuntimeError
    attr_reader :organization_id, :failed_unpublish_page_ids

    def initialize(message, organization_id: nil, failed_unpublish_page_ids: nil)
      super(message)
      @organization_id = organization_id
      @failed_unpublish_page_ids = failed_unpublish_page_ids
    end
  end

  retry_on DestroyPrivatePageError, wait: 2.seconds, attempts: 3 do |_job, error|
    Failbot.report(
      error, {
      "gh.org.id" => error.organization_id,
      "gh.pages.failed.unpublish.page.ids" => error.failed_unpublish_page_ids,
    })
    GitHub.dogstats.increment("pages.private_page.destroy", tags: ["state:failure"])
  end

  def perform(organization)
    private_page_repositories = []
    Repository.throttle do
      Repository.where(public: false, parent_id: nil, active: true,  locked: false, owner_id: organization.id).includes(:page).find_each do |repository|
        next unless repository.page
        private_page_repositories.push(repository)
      end
    end
    unpublish_pages(organization, private_page_repositories)
  end

  def unpublish_pages(organization, repositories)
    failed_unpublish_page_ids = []
    allows_private_repo_pages = organization.plan_supports?(:pages, visibility: :private)
    repositories.each do |repository|
      page = repository.page
      begin
        if page.public? && allows_private_repo_pages
          next
        end
        if page.should_soft_delete?
          Page.throttle_writes do
            if page.deleted_at.nil?
              page.soft_delete!
            end
          end
        else
          Page.throttle_writes { page.destroy }
        end
      rescue ActiveRecord::RecordNotFound
        # Do nothing
      rescue RuntimeError
        failed_unpublish_page_ids.push(page.id)
      end
    end
    if failed_unpublish_page_ids.any?
      raise DestroyPrivatePageError.new(organization_id: organization.id, failed_unpublish_page_ids: failed_unpublish_page_ids, message: "failed to unpublish some private pages.")
    else
      GitHub.dogstats.increment("pages.private_page.destroy", tags: ["state:succeed"])
    end
  end

  retry_on_recoverable_exceptions
  retry_on_dirty_exit
end
