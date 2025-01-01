# typed: true
# frozen_string_literal: true

module CodeScanning
  class AlertTimelineEvent
    attr_reader :category, :commit_oid, :environment, :file_path, :id, :logical_alert_id, :message, :ref_name_bytes, :resolution, :resolution_note, :start_line, :timestamp, :tool_version, :type, :user_id, :workflow_run_id, :request_id, :compute_status, :show_dismissal_actions, :reviewer_comment

    def initialize(category: nil, commit_oid: nil, environment: nil, file_path: nil, id: nil, logical_alert_id: nil, message: nil, ref_name_bytes: nil, resolution: nil, resolution_note: nil, start_line: nil, timestamp: nil, tool_version: nil, type: nil, user_id: nil, workflow_run_id: nil, request_id: nil, compute_status: nil, show_dismissal_actions: nil, reviewer_comment: nil)
      @category = category
      @commit_oid = commit_oid
      @environment = environment
      @file_path = file_path
      @id = id
      @logical_alert_id = logical_alert_id
      @message = message
      @ref_name_bytes = ref_name_bytes
      @resolution = resolution
      @resolution_note = resolution_note
      @start_line = start_line
      @timestamp = timestamp
      @tool_version = tool_version
      @type = type
      @user_id = user_id
      @workflow_run_id = workflow_run_id
      @request_id = request_id
      @compute_status = compute_status
      @show_dismissal_actions = show_dismissal_actions
      @reviewer_comment = reviewer_comment
    end
  end
end
