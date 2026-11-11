# frozen_string_literal: true
#              



module Vexi
  # GetFeatureFlagResponse is the response returned by the GetFeatureFlag method.
  class GetFeatureFlagResponse < GetEntityResponse
    attr_reader :feature_flag

    def initialize(name: "", feature_flag: nil, error: nil)
      super(name: name, entity: feature_flag, error: error)
      @feature_flag =      (feature_flag                        )
    end
  end
end
