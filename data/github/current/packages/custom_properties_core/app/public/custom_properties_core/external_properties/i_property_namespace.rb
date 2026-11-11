# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module ExternalProperties
    module IPropertyNamespace
      extend T::Helpers

      abstract!

      sig { abstract.returns(String) }
      def display_name; end

      sig { abstract.returns(IPropertySource) }
      def source; end
    end
  end
end
