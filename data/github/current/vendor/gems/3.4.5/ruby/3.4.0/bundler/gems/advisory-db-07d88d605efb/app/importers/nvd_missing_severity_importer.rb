# frozen_string_literal: true

class NVDMissingSeverityImporter < NVDImporter
  def source
    "nvd"
  end

  # Taken almost completely from the parent class ApplicationImporter
  # but slightly tweaked so that:
  # - don't report to slack
  # - Feed Entry resolving happens syncronously so that we can ensure reviews don't get added to curation queue
  # - Feed Entry resolving happens even w/o significant changes to the feed, as long as it has a severity
  #   (to handle case where we had imported severity already but not propogated it because apparently that's how the old curation tooling worked? eg https://advisory-inbox.githubapp.com/advisory_reviews/GHSA-m87h-fqqj-mh8j)
  def import(limit: MAX_ENTRIES)
    lock.wrap! do
      import = Import.start(self)
      progress = import.progress

      take(limit).each_slice(BATCH_SIZE) do |batch|
        identifiers = batch.pluck(:identifier)
        indexed_feed_entries = FeedEntry.where(identifier: identifiers)
          .index_by(&:identifier)

        batch.each do |attributes|
          identifier = attributes.fetch(:identifier)

          existing_entry = indexed_feed_entries[identifier]

          # With the addition of Go import, we don't have a purely chronological ordering to import.
          # This line is meant to guard against the possibility of importing older records (or the same record multiple times).
          # Right now, this will reimport if the updated date is the same.
          if existing_entry && newer_modified_date(existing_entry[:raw_payload]["modified"], attributes[:raw_payload]["modified"])
            next
          end

          feed_entry = indexed_feed_entries
            .fetch(identifier) { FeedEntry.new }

          feed_entry.attributes = attributes
          feed_entry.source ||= source

          if feed_entry.skip_import?
            progress.increment(:skipped)
            Rails.logger.info("Skipped import of feed entry for #{cve_id}")
            next
          end

          feed_entry.save! if feed_entry.changed?
          # We use indexed_feed_entries to tell if we should be doing an update or a create.
          # Keep this updated to make sure that updates to entries that were added are treated
          # as updates instead of creates -- if they are treated as creates, they error.
          indexed_feed_entries[feed_entry.identifier] = feed_entry

          if feed_entry.advisory_payload["severity"].present?
            feed_entry.mark_as_unresolved
            resolve_feed_entry(feed_entry.id)
          end
        rescue StandardError => error
          Failbot.report!(error, { ghsa_id: feed_entry.ghsa_id, identifier: identifier })
          progress.increment(:errored)
        else
          if feed_entry.id_previously_changed?
            progress.increment(:created)
          else
            progress.increment(:updated)
          end
        end
      end
    ensure
      import&.finish
    end
  end

  # Based on the auto-publication pieces of AdvisoryReviewFeedEntryMerger.merge
  # but skips a bunch of logic that allows us to force an advisory update even if feed's data hadn't changed
  def resolve_feed_entry(feed_entry_id)
    feed_entry = FeedEntry.mark_as_resolving(feed_entry_id)

    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)
    merger.importer_auto_publish
    feed_entry.mark_as_resolved
  ensure
    feed_entry = FeedEntry.find_by(id: feed_entry_id)
    feed_entry.mark_as_unresolved if feed_entry&.resolving?
  end
end
