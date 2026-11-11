# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class FeatureFlagsIndexCrumb < IndexCrumb
      sig { override.returns(String) }
      def label
        "Feature flags"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_feature_flags_path
      end
    end
  end
end
