# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Logging

      module Destination
        STDOUT = "stdout"
        SYSLOG = "syslog"
        FILE   = "file"
        NULL   = "null"
      end

      module_function

      def destination
        if destination = ENV["GH_LOG_DESTINATION"]
          return destination
        end

        if GitHub::AppEnvironment.production? && !GitHub.enterprise?
          return Destination::SYSLOG
        end

        # This implies a per-subsystem default, no overriding destination
        nil
      end

    end
  end
end
