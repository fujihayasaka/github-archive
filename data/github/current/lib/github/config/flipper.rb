# typed: true
# frozen_string_literal: true

require "flipper/config"

Flipper.configure do |config|
  config.default do
    adapter = ::Flipper::Adapters::Override.new(::Flipper::Config.enabled_adapter)
    ::Flipper.new(adapter, instrumenter: GitHub.instrumentation_service)
  end
end

module GitHub
  module Config
    module Flipper
      extend T::Sig
      class FlipperProxy < SimpleDelegator
        def preload(names)
          T.bind(self, T.untyped)

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return_value = super
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

          FlipperSubscriber.track_preload(names, duration)

          return_value
        end
      end

      sig { returns(FlipperProxy) }
      def flipper
        @flipper ||= FlipperProxy.new(::Flipper.instance)
      end
    end
  end

  extend Config::Flipper
end
