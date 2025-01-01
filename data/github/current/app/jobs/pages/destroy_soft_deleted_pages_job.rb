# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Pages
  class DestroySoftDeletedPagesJob < ApplicationJob
    queue_as :background_destroy

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    MAX_PAGES_TO_DELETE = 5000
    BATCH_SIZE = 100

    def perform
      return if GitHub.enterprise?
      return unless GitHub.flipper[:pages_destroy_soft_deleted_pages_job].enabled?

      to_destroy = Page.where("deleted_at < ?", DateTime.now - Page::SOFT_DELETION_LIMIT).limit(MAX_PAGES_TO_DELETE)

      with_write do
        to_destroy.in_batches(of: BATCH_SIZE) do |batch|
          Page.throttle { batch.destroy_all }
        end
      end
    end

  end
end
