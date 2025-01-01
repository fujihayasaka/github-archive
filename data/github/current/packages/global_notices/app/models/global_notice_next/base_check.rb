# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class BaseCheck
    def initialize(viewer:)
      @viewer = viewer
    end

    def type
      "warn"
    end

    def is_scheduled?
      false
    end

    def can_snooze?
      false
    end

    def snooze
      raise "Please implement #snooze if #can_snooze?"
    end

    def display?(_)
      should_show_notice?
    end

    def should_show_notice?
      raise "Please implement #should_show_notice?"
    end

    private

    attr_reader :viewer
  end
end
