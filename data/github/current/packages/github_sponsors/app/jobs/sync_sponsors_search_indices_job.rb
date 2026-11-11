# typed: true
# frozen_string_literal: true

class SyncSponsorsSearchIndicesJob < ApplicationJob
  queue_as :sponsors_search_indices_sync

  retry_on_dirty_exit

  def perform(sponsorable:)
    with_write { sponsorable&.synchronize_search_indices_for_sponsors }
  end
end
