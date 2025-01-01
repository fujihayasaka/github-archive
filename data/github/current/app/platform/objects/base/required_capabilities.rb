# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module RequiredCapabilities
        def required_capabilities(required_capabilities = [])
          @required_capabilities ||= required_capabilities
        end

        if Rails.env.test?
          # This is only used for testing
          def required_capabilities=(required_capabilities)
            @required_capabilities = required_capabilities
          end
        end

        def generate_input_type
          apply_required_capabilities_to_class(super)
        end

        def generate_payload_type
          apply_required_capabilities_to_class(super)
        end

        private

        def apply_required_capabilities_to_class(defn_class)
          if @required_capabilities
            defn_class.required_capabilities(@required_capabilities)
          end
          defn_class
        end
      end
    end
  end
end
