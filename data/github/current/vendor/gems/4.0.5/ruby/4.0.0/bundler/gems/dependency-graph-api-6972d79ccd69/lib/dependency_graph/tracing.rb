# frozen_string_literal: true

# This file is copied from:
# https://github.com/github/github/blob/e5fa296e10c4fcceb5c4f572b5dc561e0bb43d38/lib/github/tracing.rb
# with DG-specific modifications.

# Exposes a class method, `trace_method`, which can be used to trace a method of
# a class declaratively rather than with an inline block.
#
# In other words, rather than doing this:
#
# class MyClass
#   def my_method
#     GitHub::Telemetry.tracer.in_span("my_method") do
#       puts "Run my expensive operation!"
#     end
#   end
# end
#
#
# You can do this:
#
# class MyClass
#   include DependencyGraph::Tracing
#   trace_method :my_method
#
#   def my_method
#     puts "Run my expensive operation!
#   end
# end
module DependencyGraph
  module Tracing

    module ClassMethods
      # Traces the instance method with the given name.
      #
      # method_name - Name of the instance method to trace
      # span_name - Option name of the generated span.
      # span_kind - A symbol representing an OpenTelemetry span kind.
      #   See https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/api.md#spankind.
      # span_attribute_extractor - Optional Proc that receives an instance of the class and both the
      #   positional and keyword args of the method (i.e. `->(instance, *args, **kwargs) {}`) and
      #   returns a hash of attributes to attach to the generated span.
      # span_annotator - Optional Proc that receives an instance of the class, the generated span,
      #   the span context, and the result of the method (i.e. `->(instance, span, context, result) {}`)
      #   and can be used to attach attributes or events to the span (via `span.add_attributes`
      #   or `span.add_event`). Returns nothing.
      # tracer - Optional OpenTelemetry::Tracer::Trace instance to use to generate the span.
      #   Defaults to GitHub.tracer.
      #
      # Returns the unaltered result of the traced method.
      def trace_method(method_name,
                       span_name: [self.name&.underscore, method_name].join("#"),
                       span_kind: :internal,
                       span_attribute_extractor: nil,
                       span_annotator: nil,
                       tracer: nil)

        module_name = self.name&.demodulize || "Anonymous"
        wrapper_name = "#{module_name}TracingWrapper"

        # Define the wrapper module if it doesn't already exist
        if !const_defined?(wrapper_name, false)
          const_set(wrapper_name, Module.new)
          prepend const_get(wrapper_name)
        end

        wrapper = const_get(wrapper_name)

        wrapper.class_eval do
          define_method(method_name) do |*args, **kwargs, &block|
            computed_attributes = begin
              span_attribute_extractor&.call(self, *args, **kwargs)
            rescue StandardError => e
              DependencyGraph.logger.error(
                "span_attribute_extractor proc raised an unhandled exception",
                {
                  "code.location": method_name,
                  "code.namespace":  self.class.name,
                },
                e
              )

              raise unless Rails.env.production?

              nil
            end

            # Initialize a default Opentelemetry::Trace::Tracer instance.
            # We do this here rather than directly as a default arugment for
            # `trace_method` so that we delay selecting this default tracer
            # until runtime. This makes it easier to stub `GitHub.tracer` in
            # tests.
            tracer ||= GitHub::Telemetry.tracer

            tracer.in_span(span_name, attributes: computed_attributes, kind: span_kind) do |span, context|
              result = super(*args, **kwargs, &block)

              begin
                span_annotator&.call(self, span, context, result)
              rescue StandardError => e
                DependencyGraph.logger.error(
                  "span_annotator proc raised an unhandled exception",
                  {
                    "code.location": method_name,
                    "code.namespace":  self.class.name,
                  },
                  e
                )
                raise unless Rails.env.production?
              end

              result
            end
          end
        end
      end
    end

    # Using Sorbet, we could use:
    # mixes_in_class_methods(ClassMethods)
    # but we do not use Sorbet.

    def self.included(other)
      other.extend(ClassMethods)
    end
  end
end
