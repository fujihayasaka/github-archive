# frozen_string_literal: true

require "failbot"

require_relative "cargo_snapshot"
require_relative "cargo_api"

ENV["FAILBOT_BACKEND"] ||= "memory"
Failbot.setup(ENV, { app: "dependency-graph-api" })
Failbot.install_unhandled_exception_hook!

module Cargo
  PACKAGE_MANAGER = "rust"

  FJORD_URL = ENV.fetch("FJORD_URL", "http://localhost:8085") # production value comes from Vault
  CHECKPOINTS_URL = ENV.fetch("API_URL", "http://localhost:9596")

  # the latest created_at/updated_at DateTime (as a Unix timestamp) will
  # be used to track already-processed "latest" updates to the registry
  CRATES_IO_CHECKPOINT = "crates_io_checkpoint"

  # Scoped error types for fatal API and registry snapshot based ingest errors
  class ApiError < StandardError; end
  class SnapshotError < StandardError; end

  # execute either a full snapshot backfill over the entire
  # crates.io registry, or an API-based crawl over the latest
  # packages updates/released since the previous snapshot
  # or latest-releases pass.
  def self.run_importer(full_import: false, from_version_id: 0)
    begin
      if full_import
        Snapshot.new.import_registry_snapshot(from_version_id: from_version_id)
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
  def self.import_package(package_name:, target_version: nil)
    begin
      Api.new.import_package(package_name, target_version)
    rescue => e
      Failbot.report(e)
      raise e
    end
  end
end
