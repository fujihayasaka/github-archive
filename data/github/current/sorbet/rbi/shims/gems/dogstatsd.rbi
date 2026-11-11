# typed: strict
# frozen_string_literal: true

# Shims for monkey-patched classes defined in lib/dogstats_monkey_patch.rb

class Datadog::Statsd
  class UDSRactorProxy
    sig { returns(Integer) }
    def self.init_count; end

    sig { params(value: Integer).returns(Integer) }
    def self.init_count=(value); end

    sig { params(socket_path: String).void }
    def initialize(socket_path); end

    sig { void }
    def connect; end

    sig { params(message: String).void }
    def send_message(message); end

    sig { void }
    def close; end
  end

  class UDSSender
    sig { params(socket_path: String).void }
    def initialize(socket_path); end

    sig { params(message: String).void }
    def send_message(message); end

    sig { void }
    def close; end
  end
end
