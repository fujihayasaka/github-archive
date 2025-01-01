# typed: true
# frozen_string_literal: true

module GitHub
  class FailbotBacktrace
    class GitRPCFrameProcessor
      GIT_RPC_FRAME = "---- THE WIRE ----".freeze
      FAILBOT_COMPLIANT_FRAME = "---- THE WIRE ----:0:in `<gitrpc boundary>'".freeze

      def self.call(frame)
        frame.gsub(GIT_RPC_FRAME, FAILBOT_COMPLIANT_FRAME)
      end
    end

    class RailsRootPrefixProcessor
      RAILS_ROOT = File.join(File.realpath(GitHub::AppEnvironment.root), "").freeze
      def self.call(frame)
        frame.delete_prefix(RAILS_ROOT)
      end
    end
  end
end
