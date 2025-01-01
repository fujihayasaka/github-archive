# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ToggleableFeaturesIndexCrumb < IndexCrumb
      sig { override.returns(String) }
      def label
        "Feature previews"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_toggleable_features_path
      end
    end
  end
end
