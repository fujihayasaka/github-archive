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
          GitHub.context.push({
            actor_ip: request_context.dig(:x_real_ip),
            request_id: request_context.dig(:request_id)
          })
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
