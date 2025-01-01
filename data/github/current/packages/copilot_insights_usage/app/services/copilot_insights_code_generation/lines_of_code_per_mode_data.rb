# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class LinesOfCodePerModeData
    include GitHub::Memoizer

    MODE_MAPPING = T.let(
      {
        "completions" => "Completions",
        "inline" => "Inline",
        "ask" => "Ask",
        "edit" => "Edit",
        "agent" => "Agent",
        "custom" => "Custom"
      },
      T::Hash[String, String]
    )

    FEATURE_FOR_MODE = T.let(
      {
        "completions" => "code_completion",
        "inline"      => "chat_inline",
        "ask"         => "chat_panel_ask_mode",
        "edit"        => "chat_panel_edit_mode",
        "agent"       => "chat_panel_agent_mode",
        "custom"      => "chat_panel_custom_mode"
      },
      T::Hash[String, String]
    )

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::CategoryColumnChartPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Array[String]) }
    def get_modes
      MODE_MAPPING.keys
    end

    sig { returns(T::Array[CopilotInsightsUsage::Types::CategoryColumnChartDataPoint]) }
    memoize def data
      mode_sums = {}
      get_modes.each do |mode|
        mode_sums[mode] = {
          "Suggested additions" => 0,
          "Accepted additions" => 0,
          "Suggested deletions" => 0,
          "Accepted deletions" => 0,
        }
      end

      @usage_report.each do |day_record|
        features = day_record["totals_by_feature"] || []
        features.each do |feature_record|
          feature_name = feature_record["feature"]

          next if feature_name == "chat_panel_unknown_mode"

          mode = FEATURE_FOR_MODE.key(feature_name)
          next unless mode

          mode_sums[mode]["Suggested additions"] += feature_record["loc_suggested_to_add_sum"].to_i
          mode_sums[mode]["Accepted additions"] += feature_record["loc_added_sum"].to_i
          mode_sums[mode]["Suggested deletions"] += feature_record["loc_suggested_to_delete_sum"].to_i
          mode_sums[mode]["Accepted deletions"] += feature_record["loc_deleted_sum"].to_i
        end
      end

      get_modes.each_with_index.map do |mode, idx|
        {
          id: (idx + 1).to_s,
          label: MODE_MAPPING.fetch(mode),
          values: mode_sums[mode]
        }
      end
    end
  end
end
