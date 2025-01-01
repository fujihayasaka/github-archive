# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class FeatureFlagsIndexCrumb < IndexCrumb
      def label
        "Feature flags"
      end

      def path_name
        :devtools_feature_flags_path
      end
    end
  end
end
