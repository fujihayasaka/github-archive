# typed: strict
# frozen_string_literal: true

module OctoCore
  module Domain
    class Cache
      module TelemetryReporter
        extend T::Sig
        extend T::Helpers

        interface!

        sig { abstract.params(method_name: Symbol, hit: T::Boolean, key_count: Integer).void }
        def report_attempt(method_name:, hit:, key_count:)
        end

        sig { abstract.params(hit: T::Boolean, key_count: Integer).void }
        def report_id_attempt(hit:, key_count:)
        end
      end
    end
  end
end
