# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../orca_test_helpers"

class OrcaPipelineLogsTest < GitHub::TestCase
  include OrcaTestHelpers

  sig { params(prefix: String, count: Integer, timestamp: String).returns(GitHub::Orca::UIFriendlyLogLine) }
  def create_log(prefix, count, timestamp = Time.now.iso8601)
    GitHub::Orca::UIFriendlyLogLine.new(
            log_level_string: "INFO",
            logged_at: timestamp,
            message: "#{prefix} Log message #{count}"
          )
  end

  sig { params(status: Integer, logs: T::Array[GitHub::Orca::UIFriendlyLogLine], started_at: String, completed_at: String).returns(GitHub::Orca::Stage) }
  def create_state(status, logs, started_at = Time.now.iso8601, completed_at = Time.now.iso8601)
    GitHub::Orca::Stage.new(
       status: status,
       started_at: started_at,
       completed_at: completed_at,
       ui_friendly_logs: logs
     )
  end

  test "logs_by_stage" do
    stage2_summary = GitHub::Orca::StageSummary.new(
        order_number: 2,
        ui_friendly_name: "Stage 2",
        overall_status_string: "Completed",
    )

    stage2_details = []
    3.times do |_i|
      stage2_details << create_state(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
        [1, 2, 3].map do |count|
          create_log("stage 2 log", count)
        end
      )
    end

    stage_1_summary = GitHub::Orca::StageSummary.new(
      order_number: 1,
      ui_friendly_name: "Stage 1",
      overall_status_string: "Completed",
    )
    stage1_details = []

    stage1_log_time = "2024-04-26T12:37:20-:00"
    stage1_log_time_iso = Time.parse(stage1_log_time).iso8601.to_s
    stage1_details << create_state(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
        [1, 2, 3].map do |count|
          create_log("stage 1 log", count, stage1_log_time)
        end
      )

    pipeline_details = GitHub::Orca::PipelineDetails.new(
      stages: {
        "stage2" => GitHub::Orca::StageDetails.new(
          summary: stage2_summary,
          details: stage2_details
        ),
        "stage1" => GitHub::Orca::StageDetails.new(
          summary: stage_1_summary,
          details: stage1_details
        )
      }
    )

    stages = Orca::PipelineLogs.new(pipeline_details).stages_as_json
    assert_equal 2, stages.count
    stages.sort { |a, b| a[:order] <=> b[:order] }
    # We should have reordered the stages
    assert T.must(stages[0])[:order] < T.must(stages[1])[:order]
    assert_equal "Stage 1", T.must(stages[0])[:name]
    assert_equal "Stage 2", T.must(stages[1])[:name]

    assert_equal 3, T.must(T.must(stages[0])[:log_groups])[0][:logs].count
    # Lets check the first log message
    assert_equal "stage 1 log Log message 1", T.must(T.must(T.must(stages[0])[:log_groups])[0][:logs])[0][:message]
    # and the first log message of the second stage
    assert_equal "stage 2 log Log message 1", T.must(T.must(T.must(stages[1])[:log_groups])[0][:logs])[0][:message]
    # ensure we cast times to iso8601
    assert_equal stage1_log_time_iso, T.must(T.must(T.must(stages[0])[:log_groups])[0][:logs])[0][:logged_at]
  end
end
