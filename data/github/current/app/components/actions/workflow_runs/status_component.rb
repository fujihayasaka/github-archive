# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class StatusComponent < ApplicationComponent
      # Adding a : to the end causes a screen reader to pause after reading out the label:
      # https://github.com/github/accessibility-audits/issues/6297#issuecomment-2050413897
      CONCLUSION_DESCRIPTIONS = {
        "timed_out"       => "timed out: ",
        "failure"         => "failed: ",
        "neutral"         => "neutral: ",
        "success"         => "completed successfully: ",
        "cancelled"       => "cancelled: ",
        "action_required" => "requires action with the application: ",
        "skipped"         => "skipped: ",
        "stale"           => "marked stale by GitHub because it took too long: ",
        "startup_failure" => "failed at startup: ",
      }.freeze

      STATUS_DESCRIPTIONS = {
        "requested" => "requested: ",
        "pending" => "waiting for another serialized run to finish: ",
        "waiting" => "waiting: ",
        "queued" => "queued: ",
        "in_progress" => "currently running: "
      }

      attr_reader :size, :style, :classes, :status, :conclusion

      def initialize(status:, conclusion:, is_job: true, size: 24, style: nil, classes: nil)
        @size = size
        @status = status
        @conclusion = conclusion
        @style = style
        @classes = classes
        @is_job = is_job
      end

      def octicon_name
        return nil if octicon_name_and_color.nil?
        octicon_name_and_color[:name]
      end

      def octicon_color
        return nil if octicon_name_and_color.nil?
        octicon_name_and_color[:color]
      end

      def show_animated_spinner?
        octicon_name_and_color.nil?
      end

      def aria_text
        status == "completed" ? CONCLUSION_DESCRIPTIONS[conclusion] : STATUS_DESCRIPTIONS[status]
      end

      private

      def octicon_name_and_color
        case status
        when "requested"
          { name: "circle", color: "neutral-check" }
        when "waiting"
          { name: "clock", color: "color-fg-attention" }
        when "pending"
          { name: "clock", color: "color-fg-attention" }
        when "queued"
          { name: "dot-fill", color: "hx_dot-fill-pending-icon" }
        when "in_progress"
          # Use spinner instead.
          nil
        when "completed"
          case conclusion
          when "neutral"
            { name: "square-fill", color: "neutral-check" }
          when "success"
            { name: "check-circle-fill", color: "color-fg-success" }
          when "failure"
            { name: "x-circle-fill", color: "color-fg-danger" }
          when "cancelled"
            { name: "stop", color: "neutral-check" }
          when "action_required"
            { name: "alert", color: "color-fg-attention" }
          when "timed_out"
            { name: "x-circle-fill", color: "color-fg-danger" }
          when "skipped"
            { name: "skip", color: "neutral-check" }
          when "stale"
            { name: "circle", color: "neutral-check" }
          when "startup_failure"
            { name: "x-circle-fill", color: "color-fg-danger" }
          else
            { name: "issue-reopened", color: "neutral-check" }
          end
        else
          { name: "issue-reopened", color: "neutral-check" }
        end
      end
    end
  end
end
