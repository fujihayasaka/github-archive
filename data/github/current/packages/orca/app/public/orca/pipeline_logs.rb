# typed: strict
# frozen_string_literal: true

module Orca
  class PipelineLogs
    extend T::Sig

    Stage = T.type_alias do
      {
        order: Integer,
        log_groups: T::Array[LogGroup],
        name: String,
        status: String,
      }
    end

    LogGroup = T.type_alias do
      {
        logs: T::Array[Log],
        name: String,
        ui_group_logs: T::Boolean,
      }
    end

    Log = T.type_alias do
      {
        log_level: String,
        logged_at: String,
        message: String
      }
    end


    sig { params(pipeline_details: GitHub::Orca::PipelineDetails).void }
    def initialize(pipeline_details)
      @pipeline_details = pipeline_details
    end

    sig { returns(T::Array[Stage]) }
    def stages_as_json
      @pipeline_details.stages.map do |_key, stage|
        summary = stage.summary
        details = stage.details.to_a

        {
          order: summary.order_number,
          log_groups: details.map { |d| log_group_as_json(d) },
          name: summary.ui_friendly_name,
          status: summary.overall_status_string
        }
      end
    end

    private

    sig { params(date: String).returns(String) }
    def date_to_iso(date)
      return date if date.empty?
      Time.parse(date).iso8601.to_s
    end

    sig { params(detail: GitHub::Orca::Stage).returns(LogGroup) }
    def log_group_as_json(detail)
      logs = detail.ui_friendly_logs.to_a
      name = detail.repository_name

      {
        logs: logs.map { |l| log_as_json(l) },
        name: name,
        ui_group_logs: name.present?,
      }
    end

    sig { params(log: GitHub::Orca::UIFriendlyLogLine).returns(Log) }
    def log_as_json(log)
      {
        log_level: log.log_level_string,
        logged_at: date_to_iso(log.logged_at),
        message: log.message
      }
    end
  end
end
