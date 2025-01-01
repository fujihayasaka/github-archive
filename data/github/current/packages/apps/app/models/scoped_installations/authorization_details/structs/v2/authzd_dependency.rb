# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::AuthzdDependency
        extend T::Helpers

        requires_ancestor { V2 }

        sig { returns(T::Array[Authzd::Proto::Attribute]) }
        def authzd_proto_attributes
          version = public_send(:version)
          return [] if version.nil?

          self.properties.flat_map do |property|
            value = public_send(property) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            next if value.nil?

            if value.respond_to?(:authzd_proto_attributes)
              value.authzd_proto_attributes.each do |attribute|
                attribute.id = [versioned_id_for_property(property, version), attribute.id].join(".")
              end
            else
              Authzd::Proto::Attribute.wrap(versioned_id_for_property(property, version), value)
            end
          end.compact
        end

        sig { params(property: Symbol, version: Integer).returns(String) }
        def versioned_id_for_property(property, version)
          parts =
            case property
            when :version
              [authzd_namespace, property]
            else
              [authzd_namespace, "v#{version}", property]
            end

          parts.join(".")
        end
      end
    end
  end
end
