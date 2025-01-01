# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ToggleableFeatureCrumb < Crumb
      def label
        object.public_name
      end

      def parent
        ToggleableFeaturesIndexCrumb.new
      end

      def path_name
        :devtools_toggleable_feature_path
      end

      def path_args
        [object.slug]
      end
    end
  end
end
