# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class Data
        class << self
          sig { returns(View) }
          def default
            @default ||= T.let(load_from_json, T.nilable(View))
          end

          private

          sig { returns(View) }
          def load_from_json
            json_path = File.join(__dir__, "data.json")
            data = JSON.parse(File.read(json_path), symbolize_names: true)
            View.from_hash(data)
          rescue StandardError => e
            GitHub.dogstats.increment("mobile.copilot.paywall.data_load_error", tags: ["error_class:#{e.class.name}"])
            raise
          end
        end
      end
    end
  end
end
