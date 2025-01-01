# typed: true
# frozen_string_literal: true

require "github/request_timer"

module GitHub
  module Config
    module RequestTimer
      def request_timer
        @request_timer ||= GitHub::RequestTimer.new
      end
    end
  end

  extend Config::RequestTimer
end
