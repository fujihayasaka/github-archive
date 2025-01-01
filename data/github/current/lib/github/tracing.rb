# typed: strict
# frozen_string_literal: true

# Exposes a class method, `trace_method`, which can be used to trace a method of
# a class declaratively rather than with an inline block.
#
# In other words, rather than doing this:
#
# class MyClass
#   def my_method
#     GitHub.tracer.in_span("my_method") do
#       puts "Run my expensive operation!"
#     end
#   end
# end
#
#
# You can do this:
#
# class MyClass
#   include GitHub::Tracing
#   trace_method :my_method
#
#   def my_method
#     puts "Run my expensive operation!
#   end
# end
module GitHub
  module Tracing
    extend T::Helpers

    module ClassMethods
      extend T::Helpers

      requires_ancestor { Module }

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
      sig do
        params(
          method_name: Symbol,
          span_name: T.nilable(String),
          span_kind: T.nilable(Symbol),
          span_attribute_extractor: T.nilable(Proc), # todo: make a more specific type here without Sorbet complaining
          span_annotator: T.nilable(T.proc.params(instance: T.untyped, span: OpenTelemetry::Trace::Span, context: T.untyped, result: T.untyped).void),
          tracer: T.nilable(OpenTelemetry::Trace::Tracer)
        ).void
      end
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
            # we are not using this error except in `rescue` blocks, but we are declaring the
            # type here so that Sorbet knows that the type of `e` is not changing in this scope.
            e = T.let(nil, T.nilable(StandardError))

            computed_attributes = begin
              # using T.unsafe here because Sorbet wants to know the arguments statically,
              # but that is not possible in this case.
              T.unsafe(span_attribute_extractor)&.call(self, *args, **kwargs)
            rescue StandardError => e # rubocop:todo Lint/GenericRescue
              GitHub.logger.error(
                "span_attribute_extractor proc raised an unhandled exception",
                {
                  exception: e,
                  "code.location": method_name,
                  "code.namespace":  self.class.name,
                }
              )

              raise unless Rails.env.production?

              nil
            end

            # Initialize a default Opentelemetry::Trace::Tracer instance.
            # We do this here rather than directly as a default arugment for
            # `trace_method` so that we delay selecting this default tracer
            # until runtime. This makes it easier to stub `GitHub.tracer` in
            # tests.
            tracer ||= T.let(GitHub.tracer, OpenTelemetry::Trace::Tracer)

            tracer.in_span(span_name, attributes: computed_attributes, kind: span_kind) do |span, context|
              result = super(*args, **kwargs, &block)

              begin
                span_annotator&.call(self, span, context, result)
              rescue StandardError => e # rubocop:todo Lint/GenericRescue
                GitHub.logger.error(
                  "span_annotator proc raised an unhandled exception",
                  {
                    exception: e,
                    "code.location": method_name,
                    "code.namespace":  self.class.name,
                  }
                )
                raise unless Rails.env.production?
              end

              result
            end
          end
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
