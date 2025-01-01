# typed: true
# frozen_string_literal: true

module GitHub
  class DGit

    class Logger
      def initialize(filename)
        @filename = filename
      end
      attr_reader :filename

      def info(msg)
        log msg
        puts msg
      end

      def debug(msg)
        log msg
      end

      protected

      def log(msg)
        File.open(@filename, "a") { |fd| fd.puts Time.now.strftime("%Y-%m-%d %H:%M:%S ") + msg }
      end
    end

    # log to stdout for debug
    class DebugLogger
      def info(msg); puts msg; end
      def debug(msg); puts msg; end
    end

    class SilentLogger < Logger
      def info(msg)
        log msg
      end
    end

  end
end
