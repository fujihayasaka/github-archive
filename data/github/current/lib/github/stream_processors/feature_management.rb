# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module FeatureManagement
      autoload :FeatureFlagUpdateProcessor, "github/stream_processors/feature_management/feature_flag_update_processor"
    end
  end
end
