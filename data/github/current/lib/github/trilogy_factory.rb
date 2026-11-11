# typed: true
# frozen_string_literal: true

module GitHub
  module TrilogyFactory
    extend self

    def new(config)
      if config.key?(:resilient_properties)
        build_resilient_trilogy(config)
      else
        ::Trilogy.new(config)
      end
    end

    private

    def build_resilient_trilogy(config)
      # all keys are expected to be symbols, but some may be strings when parsed from database configuration
      trilogy_config = config.deep_symbolize_keys

      resilient_properties = trilogy_config.delete(:resilient_properties)
      resilient_properties[:instrumenter] = ActiveSupport::Notifications

      Resilient::Trilogy.new(
        trilogy_options: trilogy_config,
        resilient_properties: resilient_properties,
      )
    end
  end
end
