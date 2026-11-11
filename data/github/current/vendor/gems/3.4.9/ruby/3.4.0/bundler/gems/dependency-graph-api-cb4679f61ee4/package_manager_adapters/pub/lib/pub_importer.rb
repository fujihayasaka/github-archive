# frozen_string_literal: true

require "failbot"

require_relative "pub_api"

ENV["FAILBOT_BACKEND"] ||= "memory"
Failbot.setup(ENV, { app: "dependency-graph-api" })
Failbot.install_unhandled_exception_hook!

module Pub
  PACKAGE_MANAGER = "pub"

  FJORD_URL = ENV.fetch("FJORD_URL", "http://localhost:8085") # production value comes from Vault
  CHECKPOINTS_URL = ENV.fetch("API_URL", "http://localhost:9596")

  # the latest created_at/updated_at DateTime (as a Unix timestamp) will
  # be used to track already-processed "latest" updates to the registry
  PUB_CHECKPOINT = "pub_checkpoint"

  # Scoped error types for fatal API and registry snapshot based ingest errors
  class ApiError < StandardError; end

  # execute either a full snapshot backfill over the entire
  # Pub registry, or an API-based crawl over the latest
  # packages updates/released since the previous snapshot
  # or latest-releases pass.
  def self.run_importer(full_import: false, from_page: 1)
    begin
      if full_import
        Api.new.import_most_popular(from_page: from_page)
      else
        Api.new.import_latest_releases
      end
    rescue => e
      Failbot.report(e)
      raise e
    end
  end

  # one-off import a single package. Imports all versions by
  # default, or a particular target version (by plaintext
  # version string)
  def self.import_package(target_package:, target_versions:)
    begin
      resolved_versions = target_versions.to_s.split(";").map(&:strip)

      Api.new.import_package_releases(
        target_package: target_package.to_s,
        target_versions: resolved_versions,
        all_versions: resolved_versions.empty?)
    rescue => e
      Failbot.report(e)
      raise e
    end
  end
end
