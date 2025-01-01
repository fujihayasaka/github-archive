# frozen_string_literal: true

# Import from https://github.com/FriendsOfPHP/security-advisories
class FriendsOfPHPImporter < GitHubRepoImporter
  attr_reader :specific_advisory_path

  REPO_NWO = FriendsOfPHPAdvisory::REPO_NWO
  ADVISORY_FOLDER = ""

  # it will import only the specific advisory given by the path, or full
  # database for backfill, but defaults to updated since last import
  def initialize(specific_advisory_path: nil, backfill: false)
    @specific_advisory_path = specific_advisory_path
    @backfill = backfill

    @bulk_import = specific_advisory_path.nil?
  end

  def advisories
    return [specific_advisory] if specific_advisory_path

    return @advisories if defined? @advisories

    @advisories = advisory_paths.filter_map do |advisory_path|
      FriendsOfPHPAdvisory.initialize_from_path(advisory_path)
    rescue FriendsOfPHPAdvisory::FriendsOfPHPAdvisoryError
      # Older commits may contain outdated files, so we just skip these during a bulk import
      nil
    end
  end

  def each
    advisories.each do |advisory|
      yield advisory.importer_object
    end
  end

  # Overrides the enumerable count method
  def count
    advisories.length
  end

  def specific_advisory
    return nil unless specific_advisory_path

    @specific_advisory ||= FriendsOfPHPAdvisory.initialize_from_path(specific_advisory_path)
  end
end
