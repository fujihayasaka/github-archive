# frozen_string_literal: true

# Import from https://github.com/RustSec/advisory-db
class RustsecImporter < GitHubRepoImporter
  attr_reader :specific_advisory_path

  REPO_NWO = RustsecAdvisory::REPO_NWO
  ADVISORY_FOLDER = "crates/"

  # it will import only the specific advisory given by the path, or full
  # database for backfill, but defaults to updated since last import
  def initialize(specific_advisory_path: nil, backfill: false)
    @specific_advisory_path = specific_advisory_path
    @backfill = backfill

    @bulk_import = specific_advisory_path.nil?
  end

  # Returns an array of RustsecAdvisory objects to iterate over
  def importer_objects
    return @importer_objects if defined? @importer_objects

    importer_objects = []

    if specific_advisory_path
      importer_objects.concat(specific_advisory.importer_objects)
    else
      advisory_paths.map do |advisory_path|
        advisory = begin
          RustsecAdvisory.initialize_from_path(advisory_path)
        rescue RustsecAdvisory::RustsecAdvisoryError
          # Older commits may contain outdated files, so we just skip these during a bulk import
          nil
        end

        importer_objects.concat(advisory.importer_objects) if advisory
      end
    end

    @importer_objects = importer_objects
  end

  def each(&)
    importer_objects.each(&)
  end

  # Overrides the enumerable count method
  #
  # The count method calls each, and in this case each will enqueue an ImportJob
  #   causing 2 identical ImportJobs to be queued that created a race condition
  #   where raising an AlreadyLocked error could be raised.
  # This would also call #importer_objects twice and so #initialize twice
  def count
    importer_objects.length
  end

  # Returns a RustsecAdvisory if the specific advisory path is set
  def specific_advisory
    return nil unless specific_advisory_path

    @specific_advisory ||= RustsecAdvisory.initialize_from_path(specific_advisory_path)
  end
end
