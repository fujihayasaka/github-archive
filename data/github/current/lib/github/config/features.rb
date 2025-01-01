# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Features
      def beta_features_enrolled_by_default?
        # When set to true, overrides default enrollment for toggleable features
        # on the Feature model to be opt out.
        return true if ENV["TEST_ALL_FEATURES"] == "1"

        false
      end
    end
  end

  extend Config::Features
end
