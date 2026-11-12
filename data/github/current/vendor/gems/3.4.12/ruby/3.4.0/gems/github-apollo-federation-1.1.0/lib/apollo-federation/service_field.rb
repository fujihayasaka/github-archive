# frozen_string_literal: true

require 'graphql'
require 'apollo-federation/service'

module ApolloFederation
  module ServiceField
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      extend GraphQL::Schema::Member::HasFields

      def define_service_field
        # Only define the field if it doesn't already exist
        return if @service_field_defined

        field(:_service, Service, null: false)
        @service_field_defined = true
      end
    end

    def _service
      schema_class = context.schema.is_a?(GraphQL::Schema) ? context.schema.class : context.schema
      { sdl: schema_class.federation_sdl(context: context.to_h) }
    end
  end
end
