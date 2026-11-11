# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ToggleableFeatureCrumb < Crumb
      sig { override.returns(String) }
      def label
        object.public_name
      end

      sig { override.returns(Crumb) }
      def parent
        ToggleableFeaturesIndexCrumb.new
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_toggleable_feature_path
      end

      sig { override.returns(T::Array[T.untyped]) }
      def path_args
        [object.slug]
      end
    end
  end
end
