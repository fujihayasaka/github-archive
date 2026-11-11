require_relative "nuget_catalog"
require_relative "fjord_sink"
require_relative "utilities"
require "failbot"
require "pp"
require "time"

ENV["FAILBOT_BACKEND"] ||= "memory"
Failbot.setup(ENV, { app: "dependency-graph-api" })
Failbot.install_unhandled_exception_hook!

module Nuget
  def self.run_importer
    begin
      importer = Importer.new
      importer.process_pages
    rescue => e
      Failbot.report(e)
      raise e
    end
  end

  class Importer
    include Logging

    PACKAGE_MANAGER ="nuget"
    FJORD_URL = ENV.fetch("FJORD_URL", "http://localhost:8085") # production value comes from vault
    CHECKPOINTS_URL = ENV.fetch("API_URL", "http://localhost:9596")
    CHECKPOINT_NAME = "nuget_import"

    attr_accessor :fjord_sink, :catalog

    def initialize(fjord_sink: nil , catalog: nil)
      @fjord_sink = fjord_sink || Nuget::FjordSink.new(fjord_url: FJORD_URL, checkpoints_url: CHECKPOINTS_URL)
      @catalog = catalog || Nuget::Catalog.new
    end

    # Public: Find the latest checkpoint from the database or return nil if it doesn't exist.
    # Returns Integer if > 0 or nil
    def find_latest_checkpoint
      value = fjord_sink.get_checkpoint(CHECKPOINT_NAME)
      checkpoint = value.to_i == 0 ? nil : value.to_i
      logger.info("Found checkpoint '#{checkpoint}'")
      return checkpoint
    end

    # Public: Set our checkpoint based off of the latest commitTimeStamp processed.
    # Returns current checkpoint value.
    def set_checkpoint(value)
      raise ArgumentError, "Timestamp cannot be nil" if value.nil?
      value = Time.parse(value).to_i if value.is_a?(String)
      fjord_sink.set_checkpoint(CHECKPOINT_NAME, value)
      logger.info("Set checkpoint to #{value}")
    end

    # Public: Find a catalog page URLs from the catalog index after a timestamp.
    #   If timestamp isn't specified, return 'em all!
    def find_catalog_page_urls_after_timestamp(timestamp = nil)
      raise ArgumentError, "Timestamp must be an Integer (UNIX time)" unless timestamp.nil? || timestamp.is_a?(Integer)
      return catalog_index.map { |i| i["@id"] } if timestamp.nil?

      items = catalog_index.select { |i| Time.parse(i["commitTimeStamp"]).to_i > timestamp }
      return nil if items.empty?
      items.map { |i| i["@id"] }
    end

    # Public: Processes the packages in a page and flushes them onto kafka sink
    def process_pages
      if find_catalog_page_urls_after_timestamp(find_latest_checkpoint).nil?
        logger.info "Up to date, no new packages to process"
        return
      else
        find_catalog_page_urls_after_timestamp(find_latest_checkpoint).each do |page_url|
          start_time = Time.now.to_i
          logger.info "Processing #{page_url}..."

          catalog.find_page_and_process_packages(page_url) do |package|
            begin
              fjord_sink << generate_sink_package_from_nuget_package(package)
              logger.debug "Pushed #{package["id"]} to sink..."
            rescue => e
              logger.error package.pretty_print_inspect
              raise e
            end
          end

          flushed = fjord_sink.flush_package_releases

          # set checkpoint when flush to sink is successful, else break out of loop
          flushed ? set_checkpoint(catalog.last_processed_time_stamp) : break

          end_time = Time.now.to_i
          logger.info "Processing page took #{end_time - start_time} seconds"
        end
      end
    end

    private

    # Private: Shortcut for loading and storing the catalog index.
    # Returns an Array of Hashes
    def catalog_index
      @catalog_index ||= catalog.load_catalog_index

    end

    # Private: Map json package object into format sink expects
    #
    def generate_sink_package_from_nuget_package(package)
      release = {
        package_manager: PACKAGE_MANAGER,
        package_name: package["id"],
        package_version: package["version"],
        description: package["description"],
        authors: package["authors"],
        home_url: package["projectUrl"]
      }

      if published?(package["published"])
        # sink works with time as integers, hence the conversion before flush
        release[:published_at] = Time.parse(package["published"]).to_i
      else
        # If a package has been unpublished, utilize the catalog:commitTimeStamp to get an idea of roughly when it was unpublished.
        # We use this because the published attr is set to 1900-01-01, making it useless to persist in this case.
        release[:unpublished_at] = Time.parse(package["catalog:commitTimeStamp"]).to_i
      end

      if package.has_key?("dependencyGroups")
        release[:dependencies] ||= []
        package["dependencyGroups"].each do |dependency_group|
          if !dependency_group.nil? && !dependency_group["dependencies"].nil?
            dependency_group["dependencies"].each do |dependency|
              release[:dependencies] << { 'package_name': dependency["id"] }
              if dependency["range"].kind_of?(Array)
                release[:dependencies] << { 'requirements': "'#{dependency["range"].join(", ")}'" }
              else
                release[:dependencies] << { 'requirements': dependency["range"] }
              end
            end
          end
        end
        release[:dependencies] = release[:dependencies].compact
      end

      sink_package = { value: release.reject { |key, value| value.to_s.empty? }.to_json }
      return sink_package
    end

    # Private: Helps us check whether a nuget package is published/unpublished
    # Per Nuget Docs, (https://docs.microsoft.com/en-us/nuget/api/catalog-resource#catalog-page)
    # On nuget.org, the published value is set to the year 1900 when the package is unlisted.
    # Thus, method parses published date of a package to determine if package is still published or not.
    def published?(published_date)
      published_date = Time.parse(published_date)
      unpublished_date = Time.new(1900, 01, 01).utc
      return published_date > unpublished_date
    end
  end
end
