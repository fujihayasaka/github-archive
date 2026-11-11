# typed: strict
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module ICustomProperty
        extend T::Helpers

        include Kernel

        interface!

        private

        # Returns the properties domain accessor used to perform the mutation.
        sig { abstract.returns(CustomPropertiesCore::DomainAccessorBase) }
        def domain; end

        # Transforms the resolver result to serialize output and comply with the response payload schema.
        sig { abstract.params(result: T.untyped).returns(T.untyped) }
        def transform_result(result); end
      end
    end
  end
end
