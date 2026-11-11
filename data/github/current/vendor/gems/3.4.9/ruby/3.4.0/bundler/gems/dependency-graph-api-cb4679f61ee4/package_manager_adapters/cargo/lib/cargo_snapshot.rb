# frozen_string_literal: true

require "csv"
require "sqlite3"
require "open3"
require "json"
require "httparty"

require_relative "parsed_version"
require_relative "cargo_base"

module Cargo
  class Snapshot < Base
    # full snapshot data-dump of the entire crates.io package registry. See also:
    # https://crates.io/data-access
    # https://github.com/rust-lang/crates.io-index
    CRATES_IO_REGISTRY_SNAPSHOT_URL = "https://static.crates.io/db-dump.tar.gz"
    DOWNLOADED_SNAPSHOT_LOCATION = Dir.pwd + "/tmp/db-dump.tar.gz"
    EXTRACTED_SNAPSHOT_LOCATION = Dir.pwd + "/tmp/"

    # number of registery snapshot CSV rows to ingest
    # between progress status logging
    SNAPSHOT_PROGRESS_INTERVAL = 1000
    # number of PackageVersion (Fjord events) to publish between
    # Fjord buffer flushes and progress status logging
    EVENT_PROGRESS_INTERVAL = 50

    # to process a full registry snapshot, we write a filtered
    # subset of the data into a local SQLite DB then read well
    # formed package release data out to publish events for DG
    SQLITE_DB_NAME = Dir.pwd + "/tmp/rust_packages.db"

    def initialize(fjord_sink: nil)
      super(fjord_sink: fjord_sink)
    end

    # Batch backfill of an entire Crates.io registry snapshot.
    #
    # 1. Registry snapshot archive is downloaded from crates.io
    # 2. Targeted portions of the snapshot are ETL'd into SQLite
    # 3. Package releases and metadata are retrieved from SQLite
    # 4. Package releases are batch-written to Fjord as events
    #
    # To restart a partially-failed snapshot import run, first
    # identify *which step above the fail occurred in*, then
    # follow the appropriate steps below:
    #
    # 1. Failed during step 1 above (easy):
    #    - Restart the import in full: "./wrapper import"
    #    - This will clean up the previous snapshot and temp DB itself
    # 2. Failed during step 2 above (this is the messy one, strap in!):
    #    - Comment out:
    #        1. cleanup_snapshot_storage method
    #        2. download_hydrate_registry_snapshot method
    #        3. in extract_registry_snapshot_releases: table-ingest methods for already-fully-populated tables!
    #    - Log into SQLite console and drop partially-populated table from the DB
    #    - Restart the snapshot importer: "./wrapper import"
    # 3. Failed during step 3 or 4 above (easy):
    #    - Note the latest version ID seen from previous run (these are logged per batch published)
    #    - Restart the snapshot importer: "./wrapper restart <LAST_VERSION_ID_PUBLISHED>"
    def import_registry_snapshot(from_version_id: 0)
      if from_version_id == 0
        # clean up all leftover temp dir contents before each ETL run
        cleanup_snapshot_storage

        logger.info("Starting full Cargo registry snapshot import...")

        # download and extract .tar.gz crates.io registry snapshot
        download_hydrate_registry_snapshot

        # bootstrap and populate local SQLite DB of relevant
        # package release data from registry snapshot CSV files
        extract_registry_snapshot_releases
      end

      counter = 0

      dependencies_query = <<~SQL
        select d.kind as scope, d.req as raw_requirements, c.name
        from dependencies as d
        inner join crates as c on c.id = d.crate_id
        where d.version_id = ?
      SQL

      releases_query = <<~SQL
        select c.name, v.version, c.repository, c.documentation, c.homepage, c.description, v.license,
          v.yanked, v.created_at, v.updated_at, v.download_count, v.id as version_id
        from crates as c
        inner join versions as v on c.id = v.crate_id
        where v.id > ?
        order by v.id asc
        limit ?
      SQL

      # if restarting the app from crashed state, update this
      # to latest version ID seen as logged in previous run
      last_version_id_processed = from_version_id
      max_version_id = get_max_version_id

      # obtain each versioned package from temp storage
      while last_version_id_processed < max_version_id do
        db.query(releases_query, last_version_id_processed, EVENT_PROGRESS_INTERVAL).each do |row|
          package_name = row["name"].to_s
          raw_version = row["version"].to_s
          source_url = row["repository"].to_s # code repository URL, if declared
          description = row["description"].to_s
          docs_url = row["documentation"].to_s # documentation URL, if declared
          home_url = row["homepage"].to_s # project homepage URL, if declared
          raw_license = row["license"].to_s
          download_count = row["download_count"].to_i
          version_id = row["version_id"].to_i

          # published_at: use updated_at, fall back on created_at
          published_at = row["updated_at"].to_s.empty? ? DateTime.parse(row["created_at"]) : DateTime.parse(row["updated_at"])
          # yanked: use published at, if the package version has been revoked
          unpublished_at = row["yanked"] == "t" ? published_at : nil

          # obtain each versioned package's own dependencies for summary
          raw_dependencies = []
          db.query(dependencies_query, version_id).each do |dep_row|
            raw_dep_scope = dep_row["scope"].to_i
            raw_dep_requirements = dep_row["raw_requirements"].to_s
            dep_crate_name = dep_row["name"].to_s

            raw_package_dep = {
              package_name: dep_crate_name,
              raw_version: raw_dep_requirements,
              raw_scope: raw_dep_scope,
            }

            raw_dependencies << raw_package_dep
          end

          release = ParsedVersion.new(
            package_name: package_name,
            raw_version: raw_version,
            authors: "", # prior art indicates this is low-prio, and requires an additional CSV table ingest to resolve
            license: raw_license,
            download_count: download_count,
            description: description,
            source_url: source_url,
            docs_url: docs_url,
            home_url: home_url,
            raw_dependencies: raw_dependencies,
            raw_published_at: published_at,
            raw_unpublished_at: unpublished_at,
          )

          fjord_sink << release.to_hash
          last_version_id_processed = version_id
          counter += 1

          # periodically flush the Fjord sink and update
          # the last version ID seen for paging/restart
          if counter % EVENT_PROGRESS_INTERVAL == 0
            fjord_sink.flush_package_releases
            logger.info("flushed buffered package releases to Fjord sink" +
                        " (last version ID seen: #{last_version_id_processed}, total published: #{counter})")
          end
        end
      end

      # one last flush of remaining buffered records
      fjord_sink.flush_package_releases
      logger.info("final batch of package releases flushed to Fjord sink")
      logger.info("Backfill complete: imported total of #{counter} package releases")

      # set the current checkpoint to the time of the snapshot;
      # future API-based update crawls will want to pull all
      # package releases/updates with a created/updated at
      # timestamp greater than this
      timestamp_of_snapshot = get_registry_snapshot_timestamp
      set_checkpoint(CRATES_IO_CHECKPOINT, timestamp_of_snapshot)
      logger.info("Crates.io checkpoint updated to: #{timestamp_of_snapshot}")
    end

    private

    def db
      return @db if defined?(@db)
      @db = SQLite3::Database.new(SQLITE_DB_NAME)
      @db.results_as_hash = true

      @db
    end

    def cleanup_snapshot_storage
      logger.info("Cleaning up tmp dir contents...")
      Dir[Dir.pwd + "/tmp/*"].each do |f|
        logger.info("Cleaning up #{f} from previous run")
        FileUtils.rm_rf(f)
      end
    end

    def get_max_version_id
      max_version_id = 0
      db.query("select max(id) as max_version_id from versions limit 1").each do |row|
        max_version_id = row["max_version_id"].to_i
      end
      raise SnapshotError.new("failed to obtain max version ID for event publish paging") unless max_version_id > 0

      max_version_id
    end

    # extract registry snapshot timestamp from the downloaded bundle.
    # supply filename only for unit test purposes
    def get_registry_snapshot_timestamp
      metadata_file = resolve_metadata_json_file
      f = File.open(metadata_file, "r")
      metadata = JSON.parse(f.read)
      f.close

      DateTime.parse(metadata["timestamp"])
    end

    # ensure it's easy to stub the input files for snapshot tests
    def resolve_metadata_json_file
      Dir[EXTRACTED_SNAPSHOT_LOCATION + "/*/metadata.json"].first
    end

    def download_hydrate_registry_snapshot
      tmp_dir = "#{Dir.pwd}/tmp"
      logger.info("Defensively recreating staging dir at: #{tmp_dir}")
      FileUtils.mkdir_p(tmp_dir)

      logger.info("Downloading registry snapshot from #{CRATES_IO_REGISTRY_SNAPSHOT_URL}...")
      File.open(DOWNLOADED_SNAPSHOT_LOCATION, "wb") do |f|
        HTTParty.get(CRATES_IO_REGISTRY_SNAPSHOT_URL, stream_body: true) do |fragment|
          f.write(fragment)
        end
        f.close
        logger.info("Downloaded registry snapshot archive to: #{DOWNLOADED_SNAPSHOT_LOCATION}")
      end

      logger.info("Extracting registry snapshot to: #{EXTRACTED_SNAPSHOT_LOCATION}")
      _, _, stderr, status = Open3.popen3("tar", "-xf", DOWNLOADED_SNAPSHOT_LOCATION, "-C", EXTRACTED_SNAPSHOT_LOCATION)

      raise SnapshotError.new("failed to extract archive, got: #{stderr.read}") if !status.value.success?
      logger.info("Successfully extracted registry snapshot archive")
    end

    def extract_registry_snapshot_releases
      populate_local_crates_table
      populate_local_versions_table
      populate_local_dependencies_table
    end

    def populate_local_crates_table
      db.execute <<~SQL
        CREATE TABLE crates (
          id             INTEGER PRIMARY KEY, -- CSV field 5
          name           TEXT,                -- CSV field 7
          repository     TEXT,                -- CSV field 9
          documentation  TEXT,                -- CSV field 2
          homepage       TEXT,                -- CSV field 4
          description    TEXT,                -- CSV field 1
          created_at     TEXT,                -- CSV field 0 (ISO8601 as string)
          updated_at     TEXT                 -- CSV field 10 (ISO8601 as string)
        );
      SQL

      crates_csv_file = resolve_crates_csv_file
      successful = 0
      skipped = 0
      insert_query =
        "INSERT INTO crates (id, name, repository, documentation, homepage, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"

      # crates.csv:
      # created_at,description,documentation,downloads,homepage,id,max_upload_size,name,readme,repository,updated_at
      logger.info("Populating temp table from: #{crates_csv_file}")
      CSV.foreach(crates_csv_file, headers: true, liberal_parsing: true) do |row|
        values = [
          row.dig("id").to_i,
          row.dig("name").to_s,
          row.dig("repository").to_s,
          row.dig("documentation").to_s,
          row.dig("homepage").to_s,
          row.dig("description").to_s,
          row.dig("created_at").to_s,
          row.dig("updated_at").to_s,
        ]

        # if no PK, the record is unusable
        if values[0] == 0
          logger.debug("#{crates_csv_file}: skipping row as invalid: #{row}")
          skipped += 1
        else
          db.execute(insert_query, *values)
          successful +=1
          if successful % SNAPSHOT_PROGRESS_INTERVAL == 0
            logger.info("#{crates_csv_file}: populating crates table... (inserts: #{successful}, skipped: #{skipped})")
          end
        end
      end

      logger.info("Completed population of crates table: total rows inserted: #{successful}, total rows skipped: #{skipped}")
    end

    # allow easy stubbing of reg snapshot in test suite
    def resolve_crates_csv_file
      Dir[EXTRACTED_SNAPSHOT_LOCATION + "/*/data/crates.csv"].first
    end

    def populate_local_versions_table
      db.execute <<~SQL
        CREATE TABLE versions (
          id             INTEGER PRIMARY KEY, -- CSV field 5
          crate_id       INTEGER,             -- CSV field 0 (FK into crates table)
          version        TEXT,                -- CSV field 7
          download_count INTEGER,             -- CSV field 3
          license        TEXT,                -- CSV field 6
          yanked         TEXT,                -- CSV field 10 (one of "t" or "f")
          created_at     TEXT,                -- CSV field 2 (ISO8601 as string)
          updated_at     TEXT,                -- CSV field 9 (ISO8601 as string)
          FOREIGN KEY(crate_id) REFERENCES crates(id)
        );
      SQL

      versions_csv_file = resolve_versions_csv_file
      successful = 0
      skipped = 0
      insert_query =
        "insert into versions (id, crate_id, version, download_count, license, yanked, created_at, updated_at) values (?, ?, ?, ?, ?, ?, ?, ?)"

      # versions.csv schema:
      # crate_id,crate_size,created_at,downloads,features,id,license,num,published_by,updated_at,yanked
      logger.info("Populating temp table from: #{versions_csv_file}")
      CSV.foreach(versions_csv_file, headers: true, liberal_parsing: true) do |row|
        values = [
          row.dig("id").to_i,
          row.dig("crate_id").to_i,
          row.dig("num").to_s,
          row.dig("downloads").to_i,
          row.dig("license").to_s,
          row.dig("yanked").to_s,
          row.dig("created_at").to_s,
          row.dig("updated_at").to_s,
        ]

        # if no PK or FK, the record is unusable
        if values[0] == 0 || values[1] == 0
          logger.debug("#{versions_csv_file}: skipping row as invalid: #{row}")
          skipped += 1
        else
          db.execute(insert_query, *values)
          successful += 1
          if successful % SNAPSHOT_PROGRESS_INTERVAL == 0
            logger.info("#{versions_csv_file}: populating versions table... (inserts: #{successful}, skipped: #{skipped})")
          end
        end
      end

      logger.info("Populated versions table: total rows inserted: #{successful}, total rows skipped: #{skipped}")
    end

    # allow easy stubbing of reg snapshot in test suite
    def resolve_versions_csv_file
      Dir[EXTRACTED_SNAPSHOT_LOCATION + "/*/data/versions.csv"].first
    end

    def populate_local_dependencies_table
      db.execute <<~SQL
        CREATE TABLE dependencies (
          id               INTEGER PRIMARY KEY, -- CSV field 3
          crate_id         INTEGER,             -- CSV field 0
          kind             INTEGER,             -- CSV field 4 (0: runtime, 1: build, 2: development)
          optional         TEXT,                -- CSV field 5
          req              TEXT,                -- CSV field 6
          target           TEXT,                -- CSV field 7
          version_id       INTEGER,             -- CSV field 8
          FOREIGN KEY(crate_id) REFERENCES crates(id),
          FOREIGN KEY(version_id) REFERENCES versions(id)
        );
      SQL

      dependencies_csv_file = resolve_dependencies_csv_file
      successful = 0
      skipped = 0
      insert_query =
        "insert into dependencies (id, crate_id, kind, optional, req, target, version_id) values (?, ?, ?, ?, ?, ?, ?)"

      # dependencies.csv schema:
      # crate_id,default_features,features,id,kind,optional,req,target,version_id
      logger.info("Populating temp table from: #{dependencies_csv_file}")
      CSV.foreach(dependencies_csv_file, headers: true, liberal_parsing: true) do |row|
        values = [
          row.dig("id").to_i,
          row.dig("crate_id").to_i,
          row.dig("kind").to_i,
          row.dig("optional").to_s,
          row.dig("req").to_s,
          row.dig("target").to_s,
          row.dig("version_id").to_i,
        ]

        # if no PK or FKs, the record is unusable
        if values[0] == 0 || values[1] == 0 || values[8] == 0
          logger.debug("#{dependencies_csv_file}: skipping row as invalid: #{row}")
          skipped += 1
        else
          db.execute(insert_query, *values)
          successful += 1
          if successful % SNAPSHOT_PROGRESS_INTERVAL == 0
            logger.info("#{dependencies_csv_file}: populating dependencies table... (inserts: #{successful}, skipped: #{skipped})")
          end
        end
      end

      logger.info("Populated dependencies table: total rows inserted: #{successful}, total rows skipped: #{skipped}")
    end

    # allow easy stubbing of reg snapshot in test suite
    def resolve_dependencies_csv_file
      Dir[EXTRACTED_SNAPSHOT_LOCATION + "/*/data/dependencies.csv"].first
    end
  end
end
