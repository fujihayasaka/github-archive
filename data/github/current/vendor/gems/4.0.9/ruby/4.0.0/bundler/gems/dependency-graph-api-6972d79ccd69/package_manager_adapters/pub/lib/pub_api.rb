# frozen_string_literal: true

require "httparty"
require "json"

require_relative "parsed_version"
require_relative "pub_base"

module Pub
  class Api < Base

    # Pub API constants. See also:
    # https://pub.dev/
    # https://pub.dev/api/packages?sort=popularity&page=1
    PUB_API_BASE = "https://pub.dev/api"
    PUB_API_RATE_LIMIT_SECS = 1.0
    PUB_API_UPDATED_MAX_PAGES = 100    # equals 10k most recent package releases at 100/page
    PUB_API_POPULAR_MAX_PAGES = 200    # equals 20k most popular package releases at 100/page

    GITHUB_URL_PATTERN = /^https:\/\/github\.com.*/

    def initialize(fjord_sink: nil)
      super(fjord_sink: fjord_sink)
    end

    def import_most_popular(from_page: 1)
      successful_packages = 0
      successful_releases = 0
      skipped = 0
      candidate_checkpoint = nil

      page_num = from_page
      logger.info("Resuming full import from page #{page_num}") if from_page

      while page_num <= PUB_API_POPULAR_MAX_PAGES
        logger.info("Fetching page #{page_num} of most popular Pub packages...")

        most_popular_url = PUB_API_BASE + "/packages?sort=popularity&page=#{page_num}"
        most_popular_resp = pub_api_get(most_popular_url)
        unless most_popular_resp.ok?
          err_msg = "Error requesting page #{page_num} of most popular Pub packages, got: " +
            "HTTP #{most_popular_resp.code} #{most_popular_resp.message}"
          logger.error(err_msg)
          raise ApiError.new(err_msg)
        end
        current_page = JSON.parse(most_popular_resp.body)

        current_page["packages"].each do |pub_pkg|
          pub_pkg_name = pub_pkg["name"].to_s
          if pub_pkg_name.empty?
            logger.error("Skipping invalid recently-updated package entry (bad 'name'): #{pub_pkg_name}")
            skipped += 1
            next # non-fatal; continue
          end

          # capture all releases for the current package
          most_recent_published_at, versions_updated, versions_skipped = import_package_releases(
            target_package: pub_pkg_name,
            all_versions: true)

          skipped += versions_skipped
          successful_packages += 1
          successful_releases += versions_updated

          # capture the most recent published time seen during the backfill
          # to set as our new initial checkpoint if the run is successful
          if candidate_checkpoint.nil? || most_recent_published_at > candidate_checkpoint
            candidate_checkpoint = most_recent_published_at
          end
        end

        page_num += 1
      end

      if page_num >= PUB_API_POPULAR_MAX_PAGES
        # only record the new checkpoint if the backfill was successful
        logger.info("Backfilled #{successful_packages} packages (#{successful_releases} releases), " +
                    "skipped #{skipped} packages across #{page_num} pages")
        set_checkpoint(PUB_CHECKPOINT, candidate_checkpoint) if candidate_checkpoint
      else
        # log the last page seen for resumeable full backfill on fail
        err_msg = "Failed to fully backfill most popular 10k packages at page #{page_num}"
        logging.error(err_msg)
        raise ApiError.new(err_msg)
      end
    end

    # use the recent-updates API to obtain a list of pub packages updated since the
    # prior checkpoint was set. publish PackageRelease events for each package
    # and version ingested, including versions already captured during a previous
    # update for the same package.
    def import_latest_releases
      raw_checkpoint = get_checkpoint(PUB_CHECKPOINT)
      raise ApiError.new("Expected prior checkpoint is uninitialized. Aborting run") if raw_checkpoint == 0

      checkpoint = Time.at(raw_checkpoint).to_datetime
      logger.info("Resuming from previous checkpoint: #{checkpoint}")

      # capture all pages of pub packages with published_at
      # entries more recent than the previous checkpoint
      pkgs_to_be_updated = []

      # oldest "latest" release timestamp per page; compare to prev checkpoint
      least_recent_published = nil
      candidate_checkpoint = nil

      successful_packages = 0
      successful_releases = 0
      skipped = 0

      page_num = 1
      while page_num <= PUB_API_UPDATED_MAX_PAGES
        logger.info("Fetching page #{page_num} of recently updated Pub packages...")

        # the "updated" sort ensures each page of pub packages is ordered by published_at desc
        recents_url = PUB_API_BASE + "/packages?sort=updated&page=#{page_num}"
        recents_resp = pub_api_get(recents_url)
        unless recents_resp.ok?
          err_msg = "Error requesting page #{page_num} of recently updated pub packages," +
            "got: HTTP #{recents_resp.code} #{recents_resp.message}"
          logger.error(err_msg)
          raise ApiError.new(err_msg)
        end
        recent_updates = JSON.parse(recents_resp.body)

        # for each updated package found, we need to check the
        # all-versions endpoint for that package to obtain timestamps
        # and ensure we only track previously unseen package releases
        # for downstream ingest processing
        recent_updates["packages"].each do |pub_pkg|
          pub_pkg_name = pub_pkg["name"].to_s
          if pub_pkg_name.empty?
            logger.error("Skipping invalid recently-updated package entry (bad 'name'): #{pub_pkg_name}")
            skipped += 1
            next # non-fatal; continue
          end

          # capture all releases for the current package
          latest_pkg_published_at, versions_updated, versions_skipped = import_package_releases(
            target_package: pub_pkg_name,
            all_versions: true)

          skipped += versions_skipped
          successful_packages += 1
          successful_releases += versions_updated

          # capture the most recent published time seen during the run
          # to set as our new checkpoint if the run is successful
          if candidate_checkpoint.nil? || latest_pkg_published_at > candidate_checkpoint
            candidate_checkpoint = latest_pkg_published_at
          end

          # capture the least recent "latest" package published time seen during
          # the run to track when we encounter recently updated packages published
          # since the previous checkpoint (our trigger to stop processing!)
          if least_recent_published.nil? || latest_pkg_published_at < least_recent_published
            least_recent_published = latest_pkg_published_at
          end

          # if we've found all the most recent updates, skip remaining packages on this page
          break if least_recent_published.nil? || least_recent_published <= checkpoint
        end

        # if we've found all the most recent updates, we don't need to page farther
        break if least_recent_published.nil? || least_recent_published <= checkpoint

        page_num += 1
      end

      # on successful traversal of all packages updated since the prior
      # checkpoint, we can safely update the checkpoint for next run
      set_checkpoint(PUB_CHECKPOINT, candidate_checkpoint) if candidate_checkpoint
      logger.info("Updated #{successful_packages} packages (#{successful_releases} releases), " +
                  "skipped #{skipped} packages across #{page_num} pages")
    end

    # Ingest a single pub package (all versions or specified targets)
    def import_package_releases(target_package:, target_versions: [], all_versions: false)
      versions_msg = if target_versions.empty? || all_versions
                       "all versions"
                     else
                       "selected versions #{target_versions}"
                     end
      logger.info("Imorting Pub package releases for #{target_package} #{versions_msg}")

      pkg_url = PUB_API_BASE + "/packages/#{target_package}"
      pkg_resp = pub_api_get(pkg_url)
      unless pkg_resp.ok?
        err_msg = "Error requesting Pub package: #{target_package}, got: HTTP #{pkg_resp.code} #{pkg_resp.message}"
        logger.error(err_msg)
        raise ApiError.new(err_msg)
      end
      pkg_metadata = JSON.parse(pkg_resp.body)

      # note: "latest" release is also included in master "versions" list of releases
      raw_releases = []
      pkg_metadata["versions"].each do |candidate_release|
        candidate_version = candidate_release["version"]
        raw_releases << candidate_release if all_versions || target_versions.include?(candidate_version)
      end

      # Iterate over selected versions and publish ParsedVersion for each
      skipped = 0
      counter = 0
      max_pkg_published_at_seen = nil

      raw_releases.each do |raw_release|
        package_name = raw_release.dig("pubspec", "name").to_s
        package_version = raw_release["version"].to_s
        if package_name == "" || package_version == ""
          skipped += 1
          next
        end
        logger.info("Importing or updating package release: #{package_name} #{package_version}")

        package_description = raw_release.dig("pubspec", "description").to_s

        package_published_at = raw_release["published"].to_s
        if package_published_at == ""
          skipped += 1
          next
        end
        begin
          package_published_at = DateTime.parse(package_published_at)
        rescue Date::Error
          skipped +=1
          next
        end
        if max_pkg_published_at_seen.nil? || package_published_at > max_pkg_published_at_seen
          max_pkg_published_at_seen = package_published_at
        end
        # Pub API doesn't "unpublish" packages by policy; it deletes them in emergency situations
        # see also: https://github.com/dart-lang/pub-dev/blob/ca8dfe5f7b99c187bf7dd7c699e0a5420af9ab92/doc/help-publishing.md#discontinuing-a-package

        # capture docs, homepage, and source repository URLs if available
        package_docs_url = raw_release.dig("pubspec", "documentation").to_s
        package_home_url = raw_release.dig("pubspec", "homepage").to_s
        package_source_url = raw_release.dig("pubspec", "repository").to_s

        # attempt to heuristically match a GitHub URL to source URL if not captured above
        if package_source_url == "" && package_home_url.match(GITHUB_URL_PATTERN)
          package_source_url = package_home_url
        elsif package_source_url == "" && package_docs_url.match(GITHUB_URL_PATTERN)
          package_source_url = package_docs_url
        end
        # capture dev and runtime dependencies for registered packages; skip SDK entries
        raw_dependencies = []
        (raw_release.dig("pubspec", "dependencies") || {}).each do |dep_name, dep_version|
          next unless dep_version.is_a?(String)
          raw_dependencies << {
            package_name: dep_name,
            raw_version: dep_version,
            raw_scope: :runtime,
          }
        end
        (raw_release.dig("pubspec", "dev-dependencies") || {}).each do |dep_name, dep_version|
          next unless dep_version.is_a?(String)
          raw_dependencies << {
            package_name: dep_name,
            raw_version: dep_version,
            raw_scope: :development,
          }
        end

        release = ParsedVersion.new(
          package_name: package_name,
          raw_version: package_version,
          description: package_description,
          source_url: package_source_url,
          docs_url: package_docs_url,
          home_url: package_home_url,
          raw_dependencies: raw_dependencies,
          raw_published_at: package_published_at,
        )

        fjord_sink << release.to_hash
        counter += 1
      end

      # flush all versions published for this package
      fjord_sink.flush_package_releases
      logger.info("Flushed batch of #{counter} PackageReleases for #{target_package} to Fjord sink; skipped #{skipped}")

      return max_pkg_published_at_seen, counter, skipped
    end

    private

    # janky rate limiting for calls to the Pub API
    def pub_api_get(url)
      @prev_request_time = Time.now unless defined?(@prev_request_time)

      prev = @prev_request_time.to_f
      diff = PUB_API_RATE_LIMIT_SECS - (Time.now.to_f - prev)
      sleep(diff) if diff > 0

      response = HTTParty.get(url, headers: {
        "User-Agent": "GitHub DependencyGraph Package Release Importer",
      })
      @prev_request_time = Time.now

      response
    end
  end
end
