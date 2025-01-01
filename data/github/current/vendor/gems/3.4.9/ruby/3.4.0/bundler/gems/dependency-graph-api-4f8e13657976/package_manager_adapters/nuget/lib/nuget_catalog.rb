require "open3"
require "httparty"
require_relative "utilities"

module Nuget
  class Catalog
    include Logging, ParseJson

    DEFAULT_HOST = "https://api.nuget.org"
    NUGET_CATALOG_INDEX = "/v3/catalog0/index.json"

    attr_accessor :index_commit_time_stamp, :last_processed_time_stamp, :host

    def initialize(host: DEFAULT_HOST)
      @host = host
    end

    def load_catalog_index
      path = NUGET_CATALOG_INDEX
      response = HTTParty.get(@host << path)
      body = parse_json(response.body)
      return nil if body.nil?
      index_commit_time_stamp = body["commitTimeStamp"]
      return body["items"]
    end

    # Public: Load a page based off of its URL.
    #
    def load_page(url)
      raise ArgumentError, "Missing URL" if url.nil?

      parsed_json, exit_status, error = nil, nil, nil
      # Fork+exec the ecosystem/nuget/page_fetch Go executable to download the page and its leaves.
      Open3.popen3("./page_fetch", url.to_s) do |stdin, stdout, stderr, wait_thr|
        parsed_json = parse_json(stdout.read)
        exit_status = wait_thr.value
        error = stderr&.read
      end

      # Check exit status of page_fetch_call - if it isn't 0, something went wrong!
      if exit_status != 0
        logger.error "page_fetch_call exit status was #{exit_status} expected 0!"
        logger.error "page_fetch stderr was #{error}"
        logger.error parsed_json if parsed_json.is_a? Hash
        return nil
      end

      # Return the parsed JSON for processing
      return parsed_json
    end

    # Public: Request a page and then yield the results for each item.
    #
    def find_page_and_process_packages(page_url, &block)
      raise ArgumentError, "Missing Page URL" if page_url.nil?
      raise ArgumentError, "Missing block" if block.nil?

      page = load_page(page_url)
      # If we fail to load the page, the go downloader already tried several retries, so we can just exit
      if page.nil?
        exit 1
      end

      items = page["Items"]
      @last_processed_time_stamp = items.last["catalog:commitTimeStamp"]
      items.each do |i|
        block.call i
      end
    end
  end
end
