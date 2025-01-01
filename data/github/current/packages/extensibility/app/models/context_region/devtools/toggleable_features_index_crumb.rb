# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ToggleableFeaturesIndexCrumb < IndexCrumb
      def label
        "Feature previews"
      end

      def path_name
        :devtools_toggleable_features_path
      end
    end
  end
end
