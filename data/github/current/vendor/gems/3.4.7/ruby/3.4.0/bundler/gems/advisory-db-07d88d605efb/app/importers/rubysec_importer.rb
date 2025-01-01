# frozen_string_literal: true

# Import from https://github.com/rubysec/ruby-advisory-db
class RubysecImporter < GitHubRepoImporter
  attr_reader :specific_advisory_path, :backfill

  REPO_NWO = RubysecAdvisory::REPO_NWO
  ADVISORY_FOLDER = "gems/"

  # it will import only the specific advisory given by the path, or full
  # database for backfill, but defaults to updated since last import
  def initialize(specific_advisory_path: nil, backfill: false)
    @specific_advisory_path = specific_advisory_path
    @backfill = backfill

    @bulk_import = specific_advisory_path.nil?
  end

  # Returns an array of RubysecAdvisory objects to iterate over
  #
  # TODO: if we don't have a specific path or are going to backfill
  #   then this should return a list of new advisories that have
  #   been published since last import
  def advisories
    return [specific_advisory] if specific_advisory_path

    return @advisories if defined? @advisories

    @advisories = advisory_paths.filter_map do |advisory_path|
      RubysecAdvisory.initialize_from_path(advisory_path)
    rescue RubysecAdvisory::RubysecAdvisoryError
      # Older commits may contain outdated files, so we just skip these during a bulk import
      nil
    end
  end

  # Called by the importer
  # Returns an enumerable list of advisory importer objects
  def each
    advisories.each do |advisory|
      yield advisory.importer_object
    end
  end

  # Overrides the enumerable count method
  #
  # The count method calls each, and in this case each will enqueue an ImportJob
  #   causing 2 identical ImportJobs to be queued that created a race condition
  #   where raising an AlreadyLocked error could be raised.
  # This would also call #advisories twice and so #initialize_from_path twice
  def count
    advisories.length
  end

  # Returns a RubysecAdvisory if the specific advisory path is set
  def specific_advisory
    return nil unless specific_advisory_path

    @specific_advisory ||= RubysecAdvisory.initialize_from_path(specific_advisory_path)
  end
end
