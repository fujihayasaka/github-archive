# typed: true
# frozen_string_literal: true

module Stafftools
  module Features
    def dev_portal_feature_link(feature, show_percentage_of_calls:, show_custom_gates:)
      link = ActionController::Base.helpers.link_to(feature.name, "https://devportal.githubapp.com/feature-flags/#{feature.name}/overview")
      if show_percentage_of_calls && feature.percentage_of_calls > 0
        ActionController::Base.helpers.safe_join([link, " @ #{feature.percentage_of_calls}%"])
      elsif show_custom_gates
        ActionController::Base.helpers.safe_join([link, " groups: #{feature.custom_gates}"])
      else
        link
      end
    end

    # Returns hash with features by gate type
    # Hash values are an Array of Arrays: [[FeatureManagement::FeatureFlags::Data::V2::FeatureFlag, Link]]
    # Also returns :error key if there was a FeatureFlagDataClientError
    def enabled_feature_flags_by_gate_type(actor, current_user)
      client = T.let(FeatureManagement::FeatureFlagDataClient.new, FeatureManagement::FeatureFlagDataClient)
      result = { actor_gates: [], possibly_gates: [], inherited_gates: [] }
      actor_enabled, inherited_enabled, possibly_enabled = client.get_enabled_feature_flags_by_actor(actor.vexi_id)

      actor_enabled.each do |flag|
        result[:actor_gates] << [flag, dev_portal_feature_link(flag, show_percentage_of_calls: false, show_custom_gates: false)]
      end

      inherited_enabled.each do |flag|
        result[:inherited_gates] << [flag, dev_portal_feature_link(flag, show_percentage_of_calls: false, show_custom_gates: false)]
      end

      possibly_enabled.each do |flag|
        in_percentage_of_call = flag.percentage_of_calls < 100 && flag.percentage_of_calls > 0
        in_custom_gate = flag.custom_gates.any?
        result[:possibly_gates] << [flag, dev_portal_feature_link(flag, show_percentage_of_calls: in_percentage_of_call, show_custom_gates: in_custom_gate)]
      end

      result
    rescue FeatureManagement::FeatureFlagDataClientError => e
      { actor_gates: [], possibly_gates: [], inherited_gates: [], error: e.code }
    end
  end
end
