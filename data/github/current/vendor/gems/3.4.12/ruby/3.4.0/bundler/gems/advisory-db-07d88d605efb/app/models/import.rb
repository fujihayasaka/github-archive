# frozen_string_literal: true

class Import < ApplicationRecord
  enum :source, AdvisoryDB.sources

  def self.start(importer)
    # Ensure we record the start time prior to fetching the data for the count so we don't lose
    # anything published between fetching & starting when picking back up in a subsequent import
    started_at = Time.current

    create!(
      source: importer.source,
      started_at: started_at,
      total_count: importer.count,
      bulk: importer.bulk_import?,
    )
  end

  def finish
    update!(
      created_count: progress.count(:created),
      updated_count: progress.count(:updated),
      errored_count: progress.count(:errored),
      skipped_count: progress.count(:skipped),
      finished_at: Time.current,
    )
  end

  def progress
    @progress ||= Progress.new(
      "import:#{source}",
      total: total_count,
      counts: {
        created: created_count,
        updated: updated_count,
        errored: errored_count,
        skipped: skipped_count,
      },
    )
  end
end
