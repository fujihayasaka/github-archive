# typed: false
# frozen_string_literal: true

class PageRecycleArtifactJob < ApplicationJob
  queue_as :background_destroy

  exempt_from_tenant_context_requirement

  # Number of artifacts to keep for a public repository
  KEPT_ARTIFACTS_PUBLIC = 30
  # Number of artifacts to keep for a non public repository (private or internal)
  KEPT_ARTIFACTS_NON_PUBLIC = 1
  # Delta (number of artifacts more than the actual number to keep to query for deletion)
  KEPT_ARTIFACTS_DELTA = 3

  def perform(page_id)
    # Lookup the page
    page = Page.find_by_id(page_id)
    return unless page

    # For a non-public repro reduce the number of artifacts to keep
    if page.repository.public?
      kept_artifacts = KEPT_ARTIFACTS_PUBLIC
    else
      kept_artifacts = KEPT_ARTIFACTS_NON_PUBLIC
    end

    # Clean the artifact when total artifacts greater than max kept artifacts
    latest_artifacts = page&.latest_artifacts(limit: [KEPT_ARTIFACTS_PUBLIC, KEPT_ARTIFACTS_NON_PUBLIC].max + KEPT_ARTIFACTS_DELTA) || []
    deleted_count = latest_artifacts.count - kept_artifacts
    if deleted_count > 0
      latest_artifacts.last(deleted_count).each do |artifact|
        with_write { artifact.destroy }
      end
      GitHub.dogstats.increment("pages.page.artifact.recycle", tags: ["by:#{deleted_count}"])
    end
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
end
