# typed: true
# frozen_string_literal: true

module PullRequests
  module Orchestrations
    module DataAttributes
      extend T::Helpers

      Error = Class.new(Orchestration::Error)

      module Types
        # Shim class to deal with the lack of `Boolean` base class.
        Boolean = Class.new
      end

      module ClassMethods
        extend T::Sig
        extend T::Helpers

        requires_ancestor { Kernel }

        # Automatically generate getters and setters for the `data` column in a type safe manner. This utilizes
        # the ActiveJob serializers, so any data types that can be enqueued are allowed for storage.
        #
        # The underlying storage mechanism will have limits, be careful storing large blobs of data.
        #
        # * `name`: Name of the key in the data JSON.
        # * `klass`: The Ruby class of the value in the JSON object. Allowed types overlap with ActiveJob.
        #            See: https://api.rubyonrails.org/classes/ActiveJob/SerializationError.html
        #            Note: These are Ruby constant references and not Sorbet types. (Types::Boolean versus T::Boolean)
        # * `default`: Declare a default value returned from the getter if no non-nil value is persisted as data for
        #              the attribute.
        # * `required`: Declare if the generated setter and getter allow for nil values, defaults to true.
        # * `persisted`: Declare the data as a "virtual" attribute that is not persisted to the database.
        #                Useful for unbounded user countent that will be persisted in an appropriate location.
        sig do
          params(
            name: Symbol,
            klass: T::Class[T.anything], # TODO: This is a limitation of Sorbet runtime that we cannot reuse those types.
            default: T.untyped,
            required: T::Boolean,
            persisted: T::Boolean,
          ).void
        end
        def data(name, klass, default: nil, required: true, persisted: true)
          ivar = :"@__data_#{name}"
          attribute = Attribute.new(name:, klass:, required:, persisted:)
          data_attributes[name] = attribute
          attribute.validate!(default) if default

          T.unsafe(self).define_method("#{name}=") do |value|
            attribute.validate!(value)

            if attribute.persisted?
              T.unsafe(self).data[name] = attribute.serialize!(value)
            end

            # Inject the given value in to the memoized ivar.
            instance_variable_set(ivar, value)
          end

          T.unsafe(self).define_method(name) do
            # Memoize the getter.
            if instance_variable_defined?(ivar)
              return instance_variable_get(ivar)
            elsif !attribute.required? && attribute.not_persisted?
              return nil
            end

            if attribute.not_persisted?
              raise Error.new("Failed to load #{name}: non-persisted data attribute")
            end

            raw_value = T.unsafe(self).data[name]

            value = if raw_value.nil? && default.present?
              default
            else
              attribute.deserialize!(raw_value)
            end

            attribute.validate!(value)

            # Memoize the getter once deserialized.
            instance_variable_set(ivar, value)
          end
        end

        # Configured `data` attributes.
        sig { returns(T::Hash[Symbol, Attribute]) }
        def data_attributes
          @data_attributes ||= {}
        end
      end

      mixes_in_class_methods(ClassMethods)

      class Attribute < T::Struct
        extend T::Sig

        prop :name, Symbol
        prop :klass, T::Class[T.anything]
        prop :required, T::Boolean
        prop :persisted, T::Boolean

        BOOLEANS = [true, false].freeze

        alias persisted? persisted
        alias required? required

        # Validates that the given value conforms to the configuration.
        def validate!(value)
          if value.nil?
            if required?
              raise Error.new("Failed to validate #{name} as #{klass}: nil value when non-nil value is required")
            end
          else
            if mismatched_type?(value)
              raise Error.new("Failed to validate #{name} as #{klass}: value is a #{value.class} instead")
            end
          end
        end

        # Deserializes from the persisted value. Works with all supported ActiveJob argument types.
        def deserialize!(value)
          begin
            ActiveJob::Arguments.deserialize([value]).first
          rescue ActiveJob::DeserializationError => e
            raise Error.new("Failed to deserialize #{name} as #{klass}: #{e.message}")
          end
        end

        # Serializes for persistence. Works with all supported ActiveJob argument types.
        def serialize!(value)
          begin
            ActiveJob::Arguments.serialize([value]).first
          rescue ActiveJob::SerializationError => e
            raise Error.new("Failed to serialize #{name} as #{klass}: #{e.message}")
          end
        end

        sig { returns(T::Boolean) }
        def not_persisted? = !persisted?

        sig { params(value: T.untyped).returns(T::Boolean) }
        def mismatched_type?(value)
          # Special case because there is no true Boolean class, and T::Boolean is not guarenteed at runtime.
          if klass == Types::Boolean
            BOOLEANS.exclude?(value)
          else
            !value.is_a?(klass)
          end
        end
      end
    end
  end
end
