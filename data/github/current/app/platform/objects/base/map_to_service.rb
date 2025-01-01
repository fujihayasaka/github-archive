# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module MapToService

        module ClassMethods
          extend T::Helpers

          include GitHub::ServiceMapping::ClassMethods

          # Add this _after_ `ServiceMapping::ClassMethods` so that `super`
          # will call that inherited method, then we can fall back to checking for a mutation definition.
          def service_mapping(serviceowners: nil)
            super || (respond_to?(:mutation) && T.unsafe(self).mutation&.service_mapping(serviceowners: serviceowners))
          end

          private

          def generate_input_type
            apply_service_mapping_to_class(super)
          end

          def generate_payload_type
            apply_service_mapping_to_class(super)
          end

          def apply_service_mapping_to_class(defn_class)
            if @default_service_mapping
              defn_class.map_to_service(@default_service_mapping)
            end
            defn_class
          end
        end

        extend T::Helpers
        mixes_in_class_methods(ClassMethods)
      end
    end
  end
end
