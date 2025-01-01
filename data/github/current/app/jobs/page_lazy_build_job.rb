# typed: false
# frozen_string_literal: true

class PageLazyBuildJob < ApplicationJob
  queue_as do
    Page.page_queue.to_s
  end

  locked_by key: ->(job) { job.arguments[0] }, timeout: 5.minutes

  class RetryError < StandardError; end
  retry_on RetryError

  def perform(page_id)
    Failbot.push(
      :app => "pages",
      "gh.job.name" => self.class.name)

    GitHub.logger.info("github pages lazy build request received", {
      "gh.pages.id" => page_id,
      "gh.catalog_service" => "github/pages"
    })

    page = Page.find_by_id(page_id)

    if page.nil?
      GitHub.logger.info("GitHub pages lazy build: page not found", {
        "gh.pages.id" => page_id,
        "gh.catalog_service" => "github/pages"
      })

      return
    end

    repository = page.repository

    with_write { repository.rebuild_pages }

    Failbot.push(
      "gh.pages.id" => page_id,
      "gh.repo.id" => repository.id,
      "gh.user.id" => repository&.owner&.id,
    )
  end
end
