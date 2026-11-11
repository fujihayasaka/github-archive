# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CustomProperties
        module DeleteCustomProperty
          extend T::Helpers
          extend ActiveSupport::Concern

          include Kernel
          include CustomPropertiesCore::Errors

          abstract!

          requires_ancestor { Platform::Mutations::Base }

          def resolve(custom_property:)
            begin
              delete_custom_property(custom_property)
            rescue InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
              raise Errors::Unprocessable.new(exception.message)
            end
          end

          private

          sig { abstract.params(custom_property: T.untyped).returns(T.untyped) }
          def delete_custom_property(custom_property); end
        end
      end
    end
  end
end
