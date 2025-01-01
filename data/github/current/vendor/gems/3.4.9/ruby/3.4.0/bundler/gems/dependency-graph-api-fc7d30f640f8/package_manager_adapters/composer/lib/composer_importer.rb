require_relative "fjord_sink"
require_relative "utilities"
require_relative "parsed_version"
require "httparty"
require "failbot"
require "nokogiri"

ENV["FAILBOT_BACKEND"] ||= "memory"
Failbot.setup(ENV, { app: "dependency-graph-api" })
Failbot.install_unhandled_exception_hook!

module Composer
  def self.run_importer(full_import: false)
    begin
      importer = Importer.new
      full_import ? importer.import_package_list : importer.import_latest_releases
    rescue => e
      Failbot.report(e)
      raise e
    end
  end

  class Importer
    include Logging, ParseJson

    FJORD_URL = ENV.fetch("FJORD_URL", "http://localhost:8085") # production value comes from Vault
    CHECKPOINTS_URL = ENV.fetch("API_URL", "http://localhost:9596")

    PACKAGIST_FULL_LIST = "https://packagist.org/packages/list.json"
    DOWNLOADED_LIST_LOCATION = Dir.pwd + "/tmp/list.json"

    PACKAGIST_LATEST_RELEASES = "https://packagist.org/feeds/releases.rss"
    DOWNLOADED_LATEST_RELEASES_LOCATION = Dir.pwd + "/tmp/releases.rss"

    LIST_JSON_CHECKPOINT = "composer_list_json_import"
    RSS_CHECKPOINT =  "composer_rss_import"

    attr_accessor :fjord_sink, :releases_imported_count

    def initialize(fjord_sink: nil)
      @fjord_sink = fjord_sink || Composer::FjordSink.new(fjord_url: FJORD_URL, checkpoints_url: CHECKPOINTS_URL)
      @releases_imported_count = 0
    end

    def get_checkpoint(checkpoint_name)
      value = fjord_sink.get_checkpoint(checkpoint_name)
      checkpoint = value.to_i
      logger.info("Found checkpoint #{checkpoint_name}: '#{checkpoint}'")
      return checkpoint
    end

    def set_checkpoint(checkpoint_name, value)
      raise ArgumentError, "Checkpoint cannot be nil" if value.nil?
      value = Time.parse(value).to_i if value.is_a?(String)
      fjord_sink.set_checkpoint(checkpoint_name, value)
      logger.info("Set checkpoint '#{checkpoint_name}' to #{value}")
    end

    #### Full alphabetical-order package ingest
    def import_package_list
      # Pull down list.json locally
      logger.info("Starting full packages list import!")
      download_list_json unless File.exist?(DOWNLOADED_LIST_LOCATION)
      package_names = JSON.parse(File.read(DOWNLOADED_LIST_LOCATION))["packageNames"]

      checkpoint = get_checkpoint(LIST_JSON_CHECKPOINT)
      package_names = package_names[checkpoint..-1] unless checkpoint.nil?

      threads = []
      sink_semaphore = Mutex.new
      checkpoint_semaphore = Mutex.new
      # Iterate through list.json it and call requests for package details page
      slice_size = (package_names.count / (Etc.nprocessors.to_f * 4)).ceil
      package_names.each_slice(slice_size) do |packages_batch|
        threads << Thread.new do
          logger.info("Creating new thread at #{Time.now}..")
          packages_batch.each_slice(50) do |packages|
            packages.each do |package_name|
              logger.info("Requesting information from packagist for #{package_name}")
              package_info = get_package_info(package_name)
              # Parse appropriate info into versions to send to sink
              next if package_info.nil? || package_info.empty?
              parse_package_versions(package_info).each do |release|
                sink_semaphore.synchronize do
                  fjord_sink << release
                  self.releases_imported_count += 1
                end
              end
              checkpoint_semaphore.synchronize { checkpoint += 1 }
            end
            sink_semaphore.synchronize do
              fjord_sink.flush_package_releases
              set_checkpoint(LIST_JSON_CHECKPOINT, checkpoint)
            end
          end
        end
      end
      threads.each(&:abort_on_exception).each(&:join)
    end

    #### Latest releases RSS feed
    ### Figure out when RSS feed is updated (cron job)
    def import_latest_releases
      logger.info("Starting latest package releases import!")
      download_releases_rss unless File.exist?(DOWNLOADED_LATEST_RELEASES_LOCATION)
      xml = File.open(DOWNLOADED_LATEST_RELEASES_LOCATION) { |f| Nokogiri::XML(f) }
      rss_published_time = Time.parse(xml.xpath("//pubDate").first.text).to_i
      new_releases = xml.xpath("//guid").map { |release| release.text.split }

      checkpoint = get_checkpoint(RSS_CHECKPOINT)
      if rss_published_time <= checkpoint
        logger.info("We've already pulled the latest releases")
        return
      else
        logger.info("Checkpoint is behind this rss update, will import latest releases!")
      end

      threads = []
      sink_semaphore = Mutex.new
      # Iterate through new releases and call requests for package details page
      slice_size = (new_releases.count / (Etc.nprocessors.to_f * 4)).ceil
      new_releases.each_slice(slice_size) do |releases|
        threads << Thread.new do
          logger.info("Creating new thread at #{Time.now}..")
          releases.each do |package_name, version|
            logger.info("Requesting information from packagist for #{package_name} and version #{version}")
            package_info = get_package_info(package_name, version: version)
            # Parse appropriate info into versions to send to sink
            parse_package_versions(package_info).each do |release|
              sink_semaphore.synchronize do
                 fjord_sink << release
                 self.releases_imported_count += 1
              end
            end
          end
        end
      end
      threads.each(&:abort_on_exception).each(&:join)
      fjord_sink.flush_package_releases
      set_checkpoint(RSS_CHECKPOINT, rss_published_time)
    end

    private

    def download_releases_rss
      logger.info("Downloading package list from #{PACKAGIST_LATEST_RELEASES}")

      File.open(DOWNLOADED_LATEST_RELEASES_LOCATION, "wb") do |f|
        HTTParty.get(PACKAGIST_LATEST_RELEASES, stream_body: true) do |fragment|
          f.write(fragment)
        end
        f.close
        logger.info("Downloaded rss of latest package releases!")
      end
    end

    def download_list_json
      logger.info("Downloading package list from #{PACKAGIST_FULL_LIST}")

      File.open(DOWNLOADED_LIST_LOCATION, "wb") do |f|
        HTTParty.get(PACKAGIST_FULL_LIST, stream_body: true) do |fragment|
          f.write(fragment)
        end
        f.close
        logger.info("Downloaded package list!")
      end
    end

    def get_package_info(package_name, version: nil)
        response = HTTParty.get("https://repo.packagist.org/p2/#{package_name.strip}.json")

        unless response.ok?
          if response.code == 404
            # When doing the full import, we will get many 404s because there are packages in the full list.json that aren't published yet and therefore don't show up in the API
            # Let's send them to Splunk instead of clogging up Haystack!
            logger.error("Error requesting Composer package '#{package_name}': HTTP #{response.code} #{response.message}")
          else
            Failbot.report(RuntimeError.new, message: "Error requesting Composer package '#{package_name}': HTTP #{response.code} #{response.message}")
          end
          return {}
        end

        packages = response.to_h["packages"]
        return {} if packages.empty?

        # sometimes this endpoint will return multiple packages (??), so make sure we only grab data from the package with an exact name match
        # If we want a specific version, we return a hash of the version's info with the version number as the key
        return {} if packages[package_name].nil?

        package = expand_package_versions(packages[package_name])
        package = version.nil? ? package : package.filter { |r| r["version"] == version }

        package
    end

    # Based on https://github.com/composer/metadata-minifier/blob/main/src/MetadataMinifier.php#L22
    def expand_package_versions(versions)
      expanded = []
      expanded_version = nil
      versions.each do |version_data|
          if expanded_version.nil?
              expanded_version = version_data
              expanded.push(expanded_version)
          else
              version_data.each do |key, val|
                  if val == "__unset"
                      expanded_version.delete(key)
                  else
                      expanded_version[key] = val
                  end
              end
              expanded.push(expanded_version)
          end
      end
      return expanded
    end

    def parse_package_versions(package_versions)
      releases = []
      package_versions.each do |info|
        parsed_version = ParsedVersion.new(
          raw_version: info["version"],
          info: info,
        )
        releases << parsed_version.to_hash
      end
      releases
    end
  end

  class ParsedVersion
    # We use a shared ParsedVersion class between the one-off importer and the package manager adapter, but they send different hash formats to the sink endpoint/model
    def to_hash
      {
        value: {
          package_name: package_name,
          package_version: version,
          package_manager: PACKAGE_MANAGER,
          authors: authors,
          description: description,
          home_url: home_url,
          published_at: published_at,
          source_url: source_url,
          dependencies: dependencies.compact,
        }.reject { |key, value| value.to_s.empty? }.compact.to_json
      }
    end
  end
end
