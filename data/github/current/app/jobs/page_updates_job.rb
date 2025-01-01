# typed: true
# frozen_string_literal: true

# This Job will take care of sending over the pages record to the pages-router
class PageUpdatesJob < ApplicationJob

  queue_as :page_updates

  retry_on_dirty_exit

  # This background job acts on pageids and is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  # Don't run more than one of this job at a time
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  class PageUpdatesJobError < StandardError; end

  BATCH_SIZE = 100

  SERVICE_NAME = "page_update_processor"

  FIELDS_TO_MIRROR_IN_PAGES_DB = %w{
    id
    repository_id
    subdomain
    custom_subdomain
    public
  }.freeze

  def self.enabled?
    GitHub.multi_tenant_enterprise?
  end

  def pages_twirp_client
    return @pages_twirp_client if defined?(@pages_twirp_client)
    @pages_twirp_client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
  end

  def perform
    Failbot.push(app: "page-updates")

    page_update_count = PageUpdate.count
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "PageUpdatesJob: begin",
      "gh.pages.update.Count" => page_update_count
    )

    processed_updates = 0

    while processed_updates < page_update_count
      page_updates = PageUpdate.order(created_at: :asc).limit(BATCH_SIZE)
      updates, destroys = page_updates.partition { |update| update.event == "update_event" || update.event == "update_subdomain_event" }
      if updates.present?
        pages_to_update = Page.where(id: updates.map { |update| update.page_id }).select(*FIELDS_TO_MIRROR_IN_PAGES_DB)
        response = pages_twirp_client.process_updates(pages_to_update)
        # Delete row from page_updates table for the updated page if no error occurred
        if response.error.nil? && response.data.status == "succeed"
          ActiveRecord::Base.connected_to(role: :writing) do
            PageUpdate.where(id: updates.map(&:id)).destroy_all
            processed_updates += updates.size
            GitHub.dogstats.increment("page_updates.update_call", tags: ["state:success"])
          end
        else
          GitHub.dogstats.increment("page_updates.update_call", tags: ["state:failure"])
          raise PageUpdatesJobError, "Error occurred during page update"
        end
      end

      if destroys.present?
        # Only need the page_id list from destroys.
        destroys_page_id_list = destroys.map(&:page_id)
        response = pages_twirp_client.process_deletion(destroys_page_id_list)
        # Delete row from page_updates table for the destroyed page if no error occurred
        if response.error.nil? && response.data.status == "succeed"
          ActiveRecord::Base.connected_to(role: :writing) do
            PageUpdate.where(id: destroys.map(&:id)).destroy_all
            processed_updates += destroys.size
            GitHub.dogstats.increment("page_updates.delete_call", tags: ["state:success"])
          end
        else
          GitHub.dogstats.increment("page_updates.delete_call", tags: ["state:failure"])
          raise PageUpdatesJobError, "Error occurred during page delete"
        end
      end
    end
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "PageUpdatesJob finish",
      "gh.pages.processed.updates" => processed_updates
    )
  end
end
