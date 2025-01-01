# typed: true

module RuboCop
  module Cop
    module GitHub
      class LoggerUsage < Base
        def github_logger_usage?(node); end

        def logger_mine_usage?(node); end
      end
    end
  end
end
