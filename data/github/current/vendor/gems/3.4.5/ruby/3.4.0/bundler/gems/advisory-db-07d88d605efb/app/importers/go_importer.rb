# frozen_string_literal: true

class GoImporter < ApplicationImporter
  # this follows the naming conventions listed at https://go.dev/security/vuln/database
  BASE_URI = "https://vuln.go.dev" # is the path portion of a Go vulnerability database URL
  METADATA_URI_PATH = "index/db.json"
  INDEX_URI_PATH = "index/vulns.json"
  VULN_URI_PATH = "ID/$vuln.json" # $vuln is a Go vulnerability ID (for example, GO-2021-1234)
  # Curation specifically requested we avoid both toolchain and stdlib,
  # these are special case package names squatted on by the Go team for internal vulns.
  # https://go.dev/security/vuln/database#examples
  RESERVED_PACKAGE_NAMES = %w[stdlib toolchain].freeze

  GoImporterError = Class.new(StandardError)

  attr_reader :specific_advisory_id, :backfill

  def initialize(specific_advisory_id: nil, backfill: false)
    @specific_advisory_id = specific_advisory_id
    @backfill = backfill

    @bulk_import = specific_advisory_id.nil?
  end

  def importer_objects
    return @importer_objects if defined? @importer_objects

    @importer_objects = []
    if specific_advisory_id
      @importer_objects.concat(specific_advisory.importer_objects)
    else
      retrieve_advisory_ids.each do |advisory_id|
        advisory = advisory_from_id(advisory_id)
        @importer_objects.concat(advisory.importer_objects)
      rescue GoImporterError
        nil
      end
    end
    @importer_objects.compact!
    # Remove any import objects that have no affected packages, i.e. contained only restricted packages
    @importer_objects.reject! { |io| io[:raw_payload]["affected"].empty? }
    @importer_objects
  end

  def each(&)
    importer_objects.each(&)
  end

  private

  def specific_advisory
    return nil unless specific_advisory_id

    @specific_advisory ||= advisory_from_id(specific_advisory_id)
  end

  def database_modified_at
    return @database_modified_at if defined? @database_modified_at

    metadata = fetch(METADATA_URI_PATH)
    @database_modified_at = metadata["modified"].to_datetime
  end

  def retrieve_advisory_ids
    @backfill ? retrieve_all_advisory_ids : retrieve_updated_advisory_ids
  end

  def retrieve_all_advisory_ids
    fetch(INDEX_URI_PATH).pluck("id")
  end

  def retrieve_updated_advisory_ids
    last_import = Import.where(source: source, bulk: true).where.not(finished_at: nil).last

    if database_modified_at <= last_import.finished_at
      Rails.logger.info(
        "No new Go advisories since last import.",
        "gh.advisory_inbox.importer.go.db.modified": database_modified_at,
        "gh.advisory_inbox.importer.go.last_import.finished_at": last_import.finished_at,
      )
      return []
    end

    fetch(INDEX_URI_PATH).select { |meta| meta["modified"].to_datetime >= last_import.finished_at }.pluck("id")
  end

  def fetch(path)
    source_uri = URI("#{BASE_URI}/#{path}")
    Rails.logger.info("Fetching #{source_uri}.")
    response = Net::HTTP.get_response(source_uri)
    case response.code
    when "200"
      JSON.parse(response.body)
    when "404"
      raise GoImporterError, "#{source_uri} could not be found."
    else
      raise "HTTP response code #{response.code} when fetching #{source_uri}"
    end
  end

  def advisory_from_id(advisory_id)
    raise(GoImporterError, "Cannot import advisory") if advisory_id.blank?

    Rails.logger.info(
      "Fetching advisory from id",
      "gh.advisory_inbox.importer.go.advisory.id": advisory_id,
    )

    advisory_body = fetch(VULN_URI_PATH.sub("$vuln", advisory_id))
    Rails.logger.info(
      "Advisory found",
      "gh.advisory_inbox.importer.go.advisory.id": advisory_id,
    )
    GoAdvisory.new(raw_payload: filtered_advisory_body(advisory_body))
  end

  def filtered_advisory_body(individual_advisory)
    individual_advisory["affected"].reject! { |a| RESERVED_PACKAGE_NAMES.include? a["package"]["name"] }
    individual_advisory
  end

  delegate :count, to: :importer_objects
end
