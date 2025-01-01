# typed: true
# frozen_string_literal: true

module GitHub
  module Logging
    class LogfmtFormatter
      def initialize(default_context = {})
        @context = default_context.map do |key, value|
          "#{key}=#{value}"
        end.join(" ")
      end

      def call(severity, datetime, progname, msg)
        log_line = %Q|#{@context} now="#{datetime.utc.iso8601}" level=#{severity} msg=#{msg.inspect}\n|
        log_line.lstrip
      end
    end
  end
end
