# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module RequiredCapabilities
        # Specifies the capabilities required to access the element. You are allowed to specify multiple required
        # capabilities but only one needs to be present in order to allow access (acts as an OR).
        #
        # This directive can be called class-level few different ways:
        # - required_capabilities :foo, :bar, :baz # preferred, easiest to read
        # - required_capabilities [:foo, :bar, :baz]
        # - required_capabilities [:foo, :bar], :baz
        # - required_capabilities [:foo, :bar], [:baz]
        #
        # All the above examples are functionally equivalent and can be read as: This GraphQL element requires the
        # user's application to have the `foo`, `bar`, OR `baz` capability in order to access it.
        #
        # Application capabilities are defined in the `lib/apps/privileged.rb` file.
        sig { params(required_capabilities: T.any(Symbol, T::Array[Symbol])).returns(T::Array[Symbol]) }
        def required_capabilities(*required_capabilities)
          # flattening the array allows for backwards compatibility with the original implementation
          # which required passing in as one array of required capabilities.
          @required_capabilities ||= required_capabilities.flatten
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
