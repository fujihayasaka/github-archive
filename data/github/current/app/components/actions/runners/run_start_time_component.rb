# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class RunStartTimeComponent < ApplicationComponent
      attr_reader :started_at

      def initialize(started_at:)
        @started_at = started_at
      end

      def initial_start_time_in_words
        if @started_at + 11.seconds > Time.now
          "now"
        elsif @started_at + 46.seconds > Time.now
          # return total seconds - 1 (subtract a second since it takes a bit for the page to be sent and rendered)
          "#{(Time.now - @started_at - 1).round} seconds ago"
        else
          "#{time_ago_in_words(@started_at, include_seconds: true)} ago".gsub("about ", "")
        end
      end

    end
  end
end
