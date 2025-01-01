# frozen_string_literal: true

require "json"
require "uri"

class NVDImporter < ApplicationImporter
  NVD_API = "https://services.nvd.nist.gov/rest/json"
  PAGE_SIZE = 2000

  NVDImporterError = Class.new(StandardError)
  NVDUnavailableError = Class.new(NVDImporterError)

  def initialize(cve_id: nil)
    if cve_id.present?
      unless AdvisoryDBToolkit::CVEIDValidator.valid?(cve_id)
        raise ArgumentError, "invalid CVE ID"
      end

      @cve_id = cve_id
    else
      @bulk_import = true
    end
  end

  def each(&)
    cve_items.each(&)
  end

  private

  def cve_items
    return @cve_items if defined? @cve_items

    json_response = download_and_parse_api

    @cve_items = json_response["vulnerabilities"].map { |raw_payload| CVEItem.new(raw_payload["cve"]).importer_object }
    while (json_response.fetch("startIndex") + json_response.fetch("resultsPerPage")) < json_response.fetch("totalResults")
      sleep(AdvisoryDB.nvd_api_key.present? ? 2 : 6) # NVD's documentation (https://nvd.nist.gov/developers/start-here) requests that we sleep several seconds between requests
      json_response = download_and_parse_api(start_index: json_response["startIndex"] + json_response["resultsPerPage"])
      @cve_items.concat(json_response["vulnerabilities"].map { |raw_payload| CVEItem.new(raw_payload["cve"]).importer_object })
    end

    @cve_items
  end

  def download_and_parse_api(start_index: 0)
    uri = URI(url)

    if uri.query.present?
      uri.query += "&startIndex=#{start_index}"
    else
      uri.query = "startIndex=#{start_index}"
    end

    res = Net::HTTP.get_response(uri, { "apiKey" => AdvisoryDB.nvd_api_key })
    case res.code
    when "200"
      json_response = JSON.parse(res.body)

      # The API returns code 200 with an empty `vulnerabilities` array if the queried CVE doesn't exist.
      # This only matters when we are looking up a single CVE, i.e. this is not a bulk import.
      raise(NVDImporterError, "Looking up #{@cve_id} in NVD returned no vulnerabilities") if @cve_id && json_response["vulnerabilities"].empty?

      json_response
    when "503"
      raise NVDUnavailableError, "HTTP response code #{res.code} when fetching #{@cve_id.presence || "modified CVEs"}"
    else
      raise NVDImporterError, "HTTP response code #{res.code} when fetching #{@cve_id.presence || "modified CVEs"}"
    end
  end

  def url
    if @cve_id.present?
      "#{NVD_API}/cves/2.0?cveId=#{@cve_id}"
    else
      "#{NVD_API}/cves/2.0?resultsPerPage=#{PAGE_SIZE}&lastModStartDate=#{format_url_timestamp(last_bulk_import)}&lastModEndDate=#{format_url_timestamp(Time.current)}"
    end
  end

  def format_url_timestamp(timestamp)
    timestamp.to_time.iso8601(3).gsub("+", "%2B")
  end

  def last_bulk_import
    # Bulk import is scheduled to run daily, if we're in a new enviorment just cover the previous day.
    @last_bulk_import ||= Import.where(source: "nvd", bulk: true).where.not(finished_at: nil).last&.started_at || 1.day.ago
  end
end
