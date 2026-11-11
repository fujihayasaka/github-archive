# typed: true

# This file is a shim for sorbet to be able to find constants it needs. If this
# file is removed by a gem upgrade, it has to be recreated, otherwise sorbet
# will throw errors. See https://github.com/github/observability-experience/issues/706
# for details.

module GitHub
  module Authentication
    # source://github-telemetry//lib/github/telemetry/logs/loggable.rb#41
    def logger; end

    # source://github-telemetry//lib/github/telemetry/logs/loggable.rb#46
    def logger=(logger); end

    class << self
      # source://github-telemetry//lib/github/telemetry/logs/loggable.rb#31
      def logger; end

      # source://github-telemetry//lib/github/telemetry/logs/loggable.rb#36
      def logger=(logger); end
    end
  end
end
