# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module MapToService
        def self.included(child_class)
          child_class.include(GitHub::ServiceMapping::ClassMethods)
          child_class.include(ServiceMappingFromMutation)
        end

        def self.extended(child_class)
          child_class.extend(GitHub::ServiceMapping::ClassMethods)
          child_class.extend(ServiceMappingFromMutation)
        end

        def generate_input_type
          apply_service_mapping_to_class(super)
        end

        def generate_payload_type
          apply_service_mapping_to_class(super)
        end

        # Add this _after_ `ServiceMapping::ClassMethods` so that `super`
        # will call that inherited method, then we can fall back to checking for a mutation definition.
        module ServiceMappingFromMutation
          def service_mapping(serviceowners: nil)
            super || (respond_to?(:mutation) && mutation&.service_mapping(serviceowners: serviceowners))
          end
        end

        private

        def apply_service_mapping_to_class(defn_class)
          if @default_service_mapping
            defn_class.map_to_service(@default_service_mapping)
          end
          defn_class
        end
      end
    end
  end
end
