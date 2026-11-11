# typed: true
# frozen_string_literal: true

module Mobile
  module ClientPublicApiFeatureFlags
    # Feature flags visible to the graphQl api via viewer#featureFlags
    FLAGS = [
      :mobile_feature_flags,
      :mobile_copilot_upsell_banner,
      :mobile_copilot_o1_midconversation_model_switching_enabled
    ]
  end
end
