# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      module CommonMethods
        def package_visibility(message)
          message.value.dig(:package, :visibility).downcase.to_s
        end

        def is_public_package?(message)
          package_visibility(message) == "public"
        end

        def initialize_context(request_context)
          # TODO: get rid of this function when cleaning up packages_fix_stream_processor_memory_leak
          GitHub.context.push({
            actor_ip: request_context.dig(:x_real_ip),
            request_id: request_context.dig(:request_id)
          })
        end

        def with_context(request_context)
          GitHub.context.push({
            actor_ip: request_context.dig(:x_real_ip),
            request_id: request_context.dig(:request_id)
          }) do
            yield
            # Hack (more charitably, a "mitigation"): Clean up context keys that are pushed but never popped in the platform layer.
            # These stacks grow unbounded, causing a memory leak which causes hydro lag: see https://github.com/github/package-registry-team/issues/7850.
            # When the platform layer is fixed, we should get rid of this hack. The issue tracking that is https://github.com/github/monolith-fitness/issues/216.
            GitHub.context.pop_key(:catalog_service)
            ::Audit.context.pop_key(:catalog_service)
          end
        end

        def customer_id(owner)
          if owner.delegate_billing_to_business?
            owner.business.customer_id
          else
            owner.customer&.id
          end
        end

        def actor_id(message)
          if message.value.dig(:actor_type) == :ACTOR_TYPE_USER
            message.value.dig(:actor_id).to_i
          else
            nil
          end
        end

        def organization_id(owner)
          if owner.organization?
            owner.id
          else
            nil
          end
        end

        def trace_processor(processor, request_context)
          # TODO: Remove once https://github.com/github/github/pull/255604 is merged
          GitHub.tracer.in_span(processor.class.name.demodulize, kind: :consumer) do |_span|
            yield
          end
        end
      end
    end
  end
end
