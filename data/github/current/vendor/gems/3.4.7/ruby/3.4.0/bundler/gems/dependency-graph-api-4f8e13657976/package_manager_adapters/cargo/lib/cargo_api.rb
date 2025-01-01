# frozen_string_literal: true

require "httparty"
require "json"

require_relative "parsed_version"
require_relative "cargo_base"

module Cargo
  class Api < Base
    # API used to crawl the registry for recent releases and obtain
    # PackageRelease metadata. Details below:
    # - https://crates.io/data-access
    # - https://crates.io/policies#crawlers
    CRATES_IO_API_BASE = "https://crates.io/api/v1"
    CRATES_IO_API_RATE_LIMIT_SECS = 1.0
    CRATES_IO_API_MAX_RECENTS_PAGE = 100

    def initialize(fjord_sink: nil)
      super(fjord_sink: fjord_sink)
    end

    # use the recent-updates API to obtain a list of crates updated since the
    # prior checkpoint was set. publish PackageRelease events for each crate
    # and version ingested, including versions already captured during a previous
    # update for the same crate.
    def import_latest_releases
      raw_checkpoint = get_checkpoint(CRATES_IO_CHECKPOINT)
      raise ApiError.new("Expected prior checkpoint is uninitialized. Aborting run") if raw_checkpoint == 0

      checkpoint = Time.at(raw_checkpoint).to_datetime
      logger.info("Resuming from previous checkpoint: #{checkpoint}")

      # Step 1: capture all pages of crates with updated_at entries
      # more recent than the previous checkpoint
      updated_crates = []
      crate_updated_at = nil
      skipped = 0
      page_num = 1
      while page_num < CRATES_IO_API_MAX_RECENTS_PAGE
        logger.info("Fetching page #{page_num} of recently updated crates...")

        # the recent-updates sort ensures each page of crates is ordered by updated_at desc
        recents_url = CRATES_IO_API_BASE + "/crates?sort=recent-updates&page=#{page_num}"
        recents_resp = crates_io_api_get(recents_url)
        unless recents_resp.ok?
          err_msg = "Error requesting page #{page_num} of recently updated crates, got: HTTP #{recents_resp.code} #{recents_resp.message}"
          logger.error(err_msg)
          raise ApiError.new(err_msg)
        end
        recent_updates = JSON.parse(recents_resp.body)

        recent_updates["crates"].each do |crate|
          crate_name = crate["name"].to_s
          if crate_name.empty?
            logger.error("Skipping invalid recently-updated crate entry (bad 'name'): #{crate}")
            skipped += 1
            next # non-fatal; continue
         end

          if crate["updated_at"].to_s == ""
            logger.error("Skipping invalid recently-updated crate entry (bad 'updated_at'): #{crate}")
            skipped += 1
            next # non-fatal; continue
          end
          crate_updated_at = DateTime.parse(crate["updated_at"].to_s)
          break if crate_updated_at < checkpoint

          updated_crates << crate_name
        end
        # if we've found all the most recent updates, we don't need to page farther
        break if crate_updated_at.nil? || crate_updated_at < checkpoint

        page_num += 1
      end

      # Step 2: import API updates for all crates captured, and for
      # each version updated more recently than the previous checkpoint
      updated_crates.reverse!
      logger.info("Captured #{updated_crates.length} recently-updated crate entries to be processed...")

      new_checkpoint = nil
      successful_crates = 0
      successful_versions = 0

      begin
        updated_crates.each do |package_name|
          most_recent_updated_at, versions_updated = import_package_release(package_name: package_name, previous_checkpoint: checkpoint)
          if !most_recent_updated_at.nil? && versions_updated > 0
            successful_crates += 1
            successful_versions += versions_updated
            new_checkpoint = most_recent_updated_at
          end
        end
      ensure
        # on partial fail, bump the checkpoint to the last successful crate version updated
        set_checkpoint(CRATES_IO_CHECKPOINT, new_checkpoint) if new_checkpoint
      end

      logger.info("Updated #{successful_crates} crates (#{successful_versions} versions), skipped #{skipped} crates across #{page_num} pages")
    end

    # Ingest a single crates.io package (all versions or a specified target)
    def import_package_release(package_name:, target_version: nil, previous_checkpoint: nil)
      since_msg = previous_checkpoint ? "updated at or after #{previous_checkpoint}" : ""
      logger.info("Imorting package releases for crate: #{package_name} #{target_version} #{since_msg}")

      pkg_url = CRATES_IO_API_BASE + "/crates/#{package_name}"
      pkg_resp = crates_io_api_get(pkg_url)
      unless pkg_resp.ok?
        err_msg = "Error requesting Cargo package: #{package_name}, got: HTTP #{pkg_resp.code} #{pkg_resp.message}"
        logger.error(err_msg)
        raise ApiError.new(err_msg)
      end
      pkg_metadata = JSON.parse(pkg_resp.body)

      description = pkg_metadata["crate"]["description"]
      source_url = pkg_metadata["crate"]["repository"]
      docs_url = pkg_metadata["crate"]["documentation"]
      home_url = pkg_metadata["crate"]["homepage"]

      # capture only the versions requiring an update:
      # 1. if target_version is supplied, process only that one
      # 2. if previous checkpoint is supplied, process only versions updated more recently
      # 3. otherwise, process all versions found
      versions = []
      if target_version
        versions = pkg_metadata["versions"]
          .select { |v| v["num"] == target_version.to_s }
          .map { |v| v["num"] }
        raise ApiError.new("Crates.io reported no matching version for #{package_name} #{target_version}") if versions.empty?
      else
        versions = pkg_metadata["versions"]
          .select { |v| previous_checkpoint.nil? || (DateTime.parse(v["updated_at"]) >= previous_checkpoint) }
          .map { |v| v["num"] }
      end

      counter = 0
      crate_version_updated_at = nil
      versions.each do |package_version|
        logger.info("Importing or updating package release: #{package_name} #{package_version}")

        version_url = CRATES_IO_API_BASE + "/crates/#{package_name}/#{package_version}"
        version_resp = crates_io_api_get(version_url)
        unless version_resp.ok?
          err_msg = "Error requesting Cargo package version: #{package_name} #{package_version}, \
                     got: HTTP #{version_resp.code} #{version_resp.message}"
          logger.warn(err_msg)
          api_err = ApiError.new(err_msg)
          next # non-fatal; keep processing
        end
        version_metadata = JSON.parse(version_resp.body)

        version_id = version_metadata["version"]["id"].to_i
        created_at = version_metadata["version"]["created_at"]
        updated_at = version_metadata["version"]["updated_at"]
        raw_license = version_metadata["version"]["license"]
        download_count = version_metadata["version"]["downloads"].to_i
        yanked = !!version_metadata["version"]["yanked"]

        # published_at: use updated_at, fall back on created_at
        published_at = !updated_at.nil? ? DateTime.parse(updated_at) : DateTime.parse(created_at)
        # yanked: use published at, if the package version has been revoked
        unpublished_at = yanked ? published_at : nil
        # track most recent version updated_at stamp so caller can use for new checkpoint
        if crate_version_updated_at.nil? || crate_version_updated_at < published_at
          crate_version_updated_at = published_at
        end

        dependencies = []
        deps_url = CRATES_IO_API_BASE + "/crates/#{package_name}/#{package_version}/dependencies"
        deps_resp = crates_io_api_get(deps_url)
        unless deps_resp.ok?
          err_msg = "Error requesting Cargo package dependencies: #{package_name} #{package_version}, got: HTTP #{deps_resp.code} #{deps_resp.message}"
          logger.warn(err_msg)
          api_err = ApiError.new(err_msg)
          next # non-fatal; keep processing
        end

        deps_metadata = JSON.parse(deps_resp.body)
        raw_dependencies = deps_metadata["dependencies"].map do |dependency|
          {
            package_name: dependency["crate_id"], # oddly, this is the Crate's name
            raw_version: dependency["req"],
            raw_scope: dependency["kind"] == "normal" ? 0 : 1,
          }
        end

        release = ParsedVersion.new(
          package_name: package_name,
          raw_version: package_version,
          authors: "", # prior art indicates this isn't high-prio, and requires another API call per release to resolve
          license: raw_license,
          download_count: download_count,
          description: description,
          source_url: source_url,
          docs_url: docs_url,
          home_url: home_url,
          raw_dependencies: raw_dependencies,
          raw_published_at: published_at,
          raw_unpublished_at: unpublished_at
        )

        fjord_sink << release.to_hash
        counter += 1
      end

      # flush all versions published for this package
      fjord_sink.flush_package_releases
      logger.info("Flushed batch of #{counter} PackageReleases for crate #{package_name} to Fjord sink")

      return crate_version_updated_at, counter
    end

    private

    # janky rate limiting for calls to Crates.io (see also: https://crates.io/data-access)
    def crates_io_api_get(url)
      unless defined?(@prev_request_time)
        @prev_request_time = Time.now
      end

      prev = @prev_request_time.to_f
      diff = CRATES_IO_API_RATE_LIMIT_SECS - (Time.now.to_f - prev)
      sleep(diff) if diff > 0

      response = HTTParty.get(url, headers: {
        "User-Agent": "GitHub DependencyGraph Package Release Importer",
      })
      @prev_request_time = Time.now

      response
    end
  end
end
