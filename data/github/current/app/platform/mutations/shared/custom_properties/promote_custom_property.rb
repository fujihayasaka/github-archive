# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CustomProperties
        module PromoteCustomProperty
          extend T::Helpers
          extend ActiveSupport::Concern

          include Kernel
          include CustomPropertiesCore::Errors

          abstract!

          requires_ancestor { Platform::Mutations::Base }

          def resolve(custom_property:)
            begin
              source = custom_property.source
              business = source.is_a?(::Organization) ? source.business : source

              promote_custom_property(business, custom_property)
            rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError => exception
              raise Errors::Unprocessable, exception.message
            end
          end

          private

          sig { abstract.params(business: ::Business, custom_property: T.untyped).returns(T.untyped) }
          def promote_custom_property(business, custom_property); end
        end
      end
    end
  end
end
