# typed: true
# frozen_string_literal: true

require "badge_ruler"

module Workflows
  class BadgeComponent < ApplicationComponent
    LEFT_BASE_WIDTH = 27    # width of badge's left side without the text
    FONT_FAMILY = "'DejaVu Sans',Verdana,Geneva,sans-serif" # Using the same font ramp as shields.io
    FONT_SIZE = 11

    FAILING_STATES = StatusCheckConfig::FAILURE_STATES + StatusCheckConfig::INCOMPLETE_STATES
    PASSING = "passing"
    FAILING = "failing"
    NO_STATUS = "no status"
    UNSUPPORTED_CONCLUSIONS = %w[neutral skipped]
    SUPPORTED_CONCLUSIONS = CheckSuite.conclusions.keys - UNSUPPORTED_CONCLUSIONS

    GRADIENT_COLORS = {
      PASSING => {
        start: "#34D058",
        end: "#28A745",
      },
      FAILING => {
        start: "#D73A49",
        end: "#CB2431",
      },
      NO_STATUS => {
        start: "#959DA5",
        end: "#6A737D",
      },
    }

    STATE_NAME_POSITION = {
      PASSING => 4,
      FAILING => 5,
      NO_STATUS => 4,
    }

    STATE_BACKGROUND = {
      PASSING => "M0 0h46.939C48.629 0 50 1.343 50 3v14c0 1.657-1.37 3-3.061 3H0V0z",
      FAILING => "M0 0h40.47C41.869 0 43 1.343 43 3v14c0 1.657-1.132 3-2.53 3H0V0z",
      NO_STATUS => "M0 0h56.897C58.61 0 60 1.343 60 3v14c0 1.657-1.39 3-3.103 3H0V0z",
    }

    RIGHT_WIDTH = {
      PASSING => 50,
      FAILING => 43,
      NO_STATUS => 60,
    }

    def initialize(workflow:, state:)
      @workflow, @state = workflow, state
    end

    private

    def workflow_name
      if @workflow.starts_with?(".github")
        @workflow.split("/").last
      else
        @workflow
      end
    end

    def state_name
      if @state == StatusCheckConfig::SUCCESS
        PASSING
      elsif FAILING_STATES.include?(@state)
        FAILING
      else
        NO_STATUS
      end
    end

    def gradient_start
      GRADIENT_COLORS[state_name][:start]
    end

    def gradient_end
      GRADIENT_COLORS[state_name][:end]
    end

    def state_name_position
      STATE_NAME_POSITION[state_name]
    end

    def state_background
      STATE_BACKGROUND[state_name]
    end

    def workflow_name_width
      # BadgeRuler provides widths at 110pt and we want 11pt, so we have divide by
      # 10 here.
      ::BadgeRuler.width_of(workflow_name) / 10.0
    end

    def left_width
      (LEFT_BASE_WIDTH + workflow_name_width).ceil
    end

    def badge_width
      left_width + RIGHT_WIDTH[state_name]
    end
  end
end
