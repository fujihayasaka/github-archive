# frozen_string_literal: true

require "advisory_db/lock"

class ApplicationImporter
  BATCH_SIZE = 100
  MAX_ENTRIES = 100_000

  include Enumerable

  # return the importer class for a given source
  def self.importer_for_source(source)
    raise ArgumentError unless AdvisoryDB.source?(source)

    case source
    when "repository_advisories"
      # This requires a special case because
      # a) the REPOSITORY_ADVISORIES source was defined long ago in hydro in plural form
      # b) all the other sources are defined in singular form in hydro (eg: NVD, RUBYSEC)
      # c) the .classify code generally works for singular sources, but for plural it fails and would return RepositoryAdvisoryImporter
      # so we have to special case somewhere, and doing it here is lowest risk since the failure will happen when `rake advisory_db:import:all` is run, not in downstream code
      RepositoryAdvisoriesImporter
    when "munger"
      # munger is defined only in the test environment, and is used only in a few unit tests
      # therefore, returning the generic ApplicationImporter is fine, since it is test only
      ApplicationImporter
    else
      "#{source.classify}Importer".constantize
    end
  end

  def self.source
    source = name.underscore.delete_suffix("_importer")
    AdvisoryDB.source?(source) ? source : nil
  end

  def self.locked?(source)
    AdvisoryDB::Lock.new("import:#{source}").locked?
  end

  def self.unlocked?(source)
    AdvisoryDB::Lock.new("import:#{source}").unlocked?
  end

  def self.lock(source)
    AdvisoryDB::Lock.new("import:#{source}").lock
  end

  def self.unlock(source)
    AdvisoryDB::Lock.new("import:#{source}").unlock
  end

  def self.import(limit: MAX_ENTRIES, report_to_slack: true, **args)
    new(**args).import(limit: limit, report_to_slack: report_to_slack)
  end

  ## Auto importing
  # when rake import:all is run, it will import all importers which have not disabled auto import
  # when defining an importer, add `disable_auto_import` in it to exclude it from import:all
  def self.auto_import?
    @auto_import != false
  end

  def self.disable_auto_import
    @auto_import = false
  end

  def initialize(**args)
    # This is important so that the default ApplicationImporter#initialize can
    # accept arbitrary keyword arguments. Otherwise ApplicationImporter#import
    # will raise an error trying to pass keyword arguments (even when empty)
    # when initializing the importer instance.
  end

  def source
    self.class.source
  end

  def bulk_import?
    @bulk_import == true
  end

  def import(limit: MAX_ENTRIES, report_to_slack: true)
    lock.wrap! do
      import = Import.start(self)
      progress = import.progress
      MonitorImportForSlackJob.perform_later(import) if report_to_slack

      begin
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
              next
            end

            feed_entry.save! if feed_entry.changed?
            # We use indexed_feed_entries to tell if we should be doing an update or a create.
            # Keep this updated to make sure that updates to entries that were added are treated
            # as updates instead of creates -- if they are treated as creates, they error.
            indexed_feed_entries[feed_entry.identifier] = feed_entry

            if feed_entry.previous_changes_significant?
              feed_entry.mark_as_unresolved
              ResolveFeedEntryJob.perform_later(feed_entry.id)
            end
          rescue StandardError => error
            Failbot.report!(error, { failure_type: "#{self.class.name.underscore}.feed_entry_errored", ghsa_id: feed_entry.ghsa_id, identifier: identifier })
            progress.increment(:errored)
            AdvisoryDB.stats.increment(
              "importers.#{self.class.name}",
              tags: AdvisoryDB.dogtags(event: :errored),
            )
          else
            if feed_entry.id_previously_changed?
              progress.increment(:created)
              AdvisoryDB.stats.increment(
                "importers.#{self.class.name}",
                tags: AdvisoryDB.dogtags(event: :created_feed_entry),
              )
            else
              progress.increment(:updated)
              AdvisoryDB.stats.increment(
                "importers.#{self.class.name}",
                tags: AdvisoryDB.dogtags(event: :updated_feed_entry),
              )
            end
          end
        end
      rescue StandardError => error
        Failbot.report!(error, { failure_type: "#{self.class.name.underscore}_crashed" })
        AdvisoryDB.stats.event(
          "#{self.class.name} crashed",
          error.message,
          alert_type: "error",
          tags: AdvisoryDB.dogtags(failure_type: :"importers.#{self.class.name.underscore}.crash", error_message: error.message),
        )
      ensure
        import&.finish
      end

      AdvisoryDB.stats.increment(
        "importers.#{self.class.name}",
        tags: AdvisoryDB.dogtags(event: :importer_run_finish),
      )
    end
  end

  def lock
    @lock ||= AdvisoryDB::Lock.new("import:#{source}")
  end

  def newer_modified_date(a, b)
    return a.to_datetime > b.to_datetime if a.present? && b.present?

    a.present?
  end
end
