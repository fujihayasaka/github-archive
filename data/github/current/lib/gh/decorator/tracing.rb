# typed: strict
# frozen_string_literal: true

module GH
  module Decorator
    module Tracing
      extend GH::Decorator

      # This decorator _requires_ the decorable to be a GH::Domain. It reports distributed tracing data on the
      # method call being decorated.
      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        formatted_method_name = method_name.to_s

        package = GitHub.packageowners.package_for_type(decorable)

        # Remove packages prefix for shorter representation in span
        domain_name = package.gsub("packages/", "")

        domain_class = T.cast(decorable, T.class_of(GH::Domain::Base))
        accessor_name = domain_class.accessor_name

        tracer = self.tracer

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          domain = T.cast(self, GH::Domain::Base)
          calling_service = domain.caller_service.to_s.underscore
          attributes = {
            "calling_catalog_service" => calling_service,
            "code.namespace" => decorable.to_s,
            "code.function" => formatted_method_name,
          }

          span_name = if accessor_name
            "domain.#{domain_name}.#{accessor_name}.#{formatted_method_name}"
          else
            "domain.#{domain_name}.#{formatted_method_name}"
          end

          tracer.in_span(span_name, attributes: attributes, kind: :internal) do
            super(*args, **kwargs, &block)
          end
        end
      end

      @_tracer = T.let(nil, T.nilable(OpenTelemetry::SDK::Trace::Tracer))

      sig { returns(OpenTelemetry::SDK::Trace::Tracer) }
      def self.tracer
        @_tracer ||= GitHub::Telemetry.tracer("domain.call")
      end
    end
  end
end
