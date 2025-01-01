# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class FeatureFlagCrumb < Crumb
      sig { override.returns(String) }
      def label
        object.name
      end

      sig { override.returns(Crumb) }
      def parent
        FeatureFlagsIndexCrumb.new
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_feature_flag_path
      end

      sig { override.returns(T::Array[T.untyped]) }
      def path_args
        [object.name]
      end
    end
  end
end
