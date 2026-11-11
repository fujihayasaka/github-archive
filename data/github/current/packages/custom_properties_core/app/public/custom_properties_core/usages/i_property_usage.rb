# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Usages
    module IPropertyUsage
      extend T::Helpers

      include Kernel

      interface!

      sig { abstract.returns(Integer) }
      def definition_id; end

      sig { abstract.returns(Integer) }
      def resource_id; end

      sig { abstract.returns(String) }
      def resource_type; end
    end
  end
end
