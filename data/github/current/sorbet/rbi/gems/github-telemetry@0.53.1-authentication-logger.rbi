# typed: true

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
