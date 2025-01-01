# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    # This module should be included in any module that will execute in the same mode as any other tracers. This defines
    # base methods that get called for a tracer so that all other tracers in the mode can call `super` into the methods
    # in here, instead of yielding themselves.
    #
    # For example, platform_execute is a method defined by us and used to wrap our full execution of a graphql query.
    # so, any tracers that want to execute some code _after_ the full query has been executed will do something along
    # the lines of the example below:

    # include Platform::Tracing::DefaultTracer Base
    # def platform_execute
    #   result = super
    #   my_custom_after_trace
    #   result
    # end
    #
    # def my_custom_after_trace
    #   GitHub.dogstats.increment("woohoo.query_done")
    # end
    module DefaultTracerBase
      def platform_execute
        yield
      end
    end
  end
end
