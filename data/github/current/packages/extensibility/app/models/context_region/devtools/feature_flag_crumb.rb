# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class FeatureFlagCrumb < Crumb
      def label
        object.name
      end

      def parent
        FeatureFlagsIndexCrumb.new
      end

      def path_name
        :devtools_feature_flag_path
      end

      def path_args
        [object.name]
      end
    end
  end
end
