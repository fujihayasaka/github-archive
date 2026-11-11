# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningCodeqlAction < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeqlActionHelpers

  # Handle a status report
  put "/repositories/:repository_id/code-scanning/analysis/status", read_from_replicas: true, operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/codeql-action-reviewers"
    repo = find_repo!

    # Check that the CodeQL Action is usable on the given repo.
    ensure_read_access_and_codeql_action_enabled!(repo, forbid: repo.public?)

    data = receive_with_schema("code-scanning-analysis", "status")
    ensure_commit_oid_format!(repo, data["commit_oid"])
    pull = find_pull_request_from_ref(repo, data["ref"])

    # Check that the right `security-events` permission is available. In general, we only
    # require `security-events: read`. We check for `security-events: write` later if this
    # status report is used to mark a Code Scanning analysis as "in progress".
    control_access :read_code_scanning,
                    resource: pull || repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true

    deliver_error_if_archived! repo

    %w[started_at action_started_at completed_at].each do |timestamp_field|
      begin
        data[timestamp_field] = DateTime.parse(data[timestamp_field]) if data[timestamp_field].present?
      rescue ArgumentError
        deliver_error!(400, message: "#{timestamp_field} is not a valid date")
      end
    end

    if data["event_reports"].present?
      %w[started_at completed_at].each do |timestamp_field|
        begin
          data["event_reports"].each_with_index do |event_report, i|
            event_report[timestamp_field] = DateTime.parse(event_report[timestamp_field]) if event_report[timestamp_field].present?
          rescue ArgumentError
            deliver_error!(400, message: "event_reports[#{i}].#{timestamp_field} is not a valid date")
          end
        end
      end
    end

    # Only call `store_code_scanning_action_in_progress` if `analysis_kinds` indicates
    # that the status report is for Code Scanning. That information should be available for
    # reports from the `init` Action. We will check that the :write_code_scanning permission
    # is available.
    mark_code_scanning_in_progress =
      GitHub::CodeQL::Action.is_code_scanning_status_report?(data) &&
      data["action_name"] == "init" &&
      data["status"] == "starting" &&
      access_allowed?(:write_code_scanning,
                      resource: pull || repo,
                      allow_integrations: true,
                      allow_user_via_granular_actor: true)

    if mark_code_scanning_in_progress
      with_write do
        store_code_scanning_action_in_progress(repo, data)
      end
    end

    GitHub::CodeQL::Action.report_status(repo, data)

    deliver_empty(status: 200)
  end

  # The maximum number of features that can be requested.
  MAX_FEATURES = 25

  get "/repositories/:repository_id/code-scanning/codeql-action/features", operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/codeql-action-reviewers"

    deliver_error! 404 if GitHub.enterprise?

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    # Check that the CodeQL Action is usable on the given repo.
    ensure_read_access_and_codeql_action_enabled!(repo, forbid: repo.public?)

    control_access :read_code_scanning,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    requested_features = nil

    if params.has_key?("features")
      requested_features = params["features"].split(",").map(&:strip)

      if requested_features.length > MAX_FEATURES
        deliver_error! 400, message: "Can request a maximum of #{MAX_FEATURES} features."
      end
    end

    deliver(:raw, GitHub::CodeQL::Action.feature_flags_for(repo, requested_features), status: 200)
  end
end
