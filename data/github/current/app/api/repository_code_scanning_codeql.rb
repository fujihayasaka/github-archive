# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningCodeql < Api::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # Upload a status report for building a CodeQL database
  put "/repositories/:repository_id/code-scanning/codeql/status", operation_id: "code-scanning/put-codeql-status", skip_rate_limit: true do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    # This endpoint is designed to only be called on the bulk builder repository
    #
    # codeql/bulk-builder is not supported in Proxima
    deliver_error!(404) unless repo.nwo == "codeql/bulk-builder" # rubocop:disable GitHub/DoNotAllowNameWithOwner

    control_access :write_code_scanning,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    # overwrite consecutive_build_failures if build succeeded, otherwise increment it
    config = CodeqlBulkBuilderConfig.find_by!(repository_id: data["repository_id"], language: data["language"])
    if data["status"] == "success"
      config.update(consecutive_build_failures: 0) if !config.consecutive_build_failures.zero?
    else
      # Inactivate repos that have failed or were cancelled 3 times in a row
      if config.consecutive_build_failures < 2
        config.update(consecutive_build_failures: config.consecutive_build_failures + 1)
      else
        config.update(is_active: false, consecutive_build_failures: config.consecutive_build_failures + 1)
        GitHub.dogstats.count("code_scanning.remote_queries.autobuild", 1, tags: ["action:config_deactivated"])
      end
    end

    begin
      data["enqueued_at"] = DateTime.parse(data["enqueued_at"]) if data["enqueued_at"].present?
      data["enqueued_at"] = nil if data["enqueued_at"].blank?
    rescue ArgumentError
      deliver_error!(400, message: "enqueued_at is not a valid date")
    end
    begin
      data["started_at"] = DateTime.parse(data["started_at"]) if data["started_at"].present?
      data["started_at"] = nil if data["started_at"].blank?
    rescue ArgumentError
      deliver_error!(400, message: "started_at is not a valid date")
    end
    begin
      data["completed_at"] = DateTime.parse(data["completed_at"]) if data["completed_at"].present?
      data["completed_at"] = nil if data["completed_at"].blank?
    rescue ArgumentError
      deliver_error!(400, message: "completed_at is not a valid date")
    end

    GlobalInstrumenter.instrument("code_scanning.codeql_bulk_builder_status", data)
  end
end
