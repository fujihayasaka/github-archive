# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Usages
    module IPropertyResource
      extend T::Helpers

      interface!

      sig { abstract.returns(T.nilable(Integer)) }
      def properties_resource_id; end

      sig { abstract.returns(String) }
      def properties_resource_type; end
    end
  end
end
