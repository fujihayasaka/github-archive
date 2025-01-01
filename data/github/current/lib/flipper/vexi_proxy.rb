# typed: true
# frozen_string_literal: true

# Needed to reference Flipper::Config::ALLOW_OVER_ACTOR_LIMIT
require "flipper/config"

# Allow GitHub features to determine if they should use Vexi or Flipper for the feature flag check.
#
# The VexiProxy module is prepended to Flipper::Feature itself

require "feature_management/feature_flag_as_flipper_actor"

module Flipper
  module VexiProxy

    def enabled?(thing = nil)
      T.bind(self, T.untyped)

      if GitHub.use_flipper_vexi_proxy_redirect
        # name can be either a string or a symbol. Convert it to a string for consistency
        converted_name = name.to_s.downcase

        # Check if the feature flag name is included in any of these exclusion lists
        if Flipper::Config::ALLOW_OVER_ACTOR_LIMIT.include?(converted_name) || converted_name.starts_with?("synthetictest_data_change_e2e")
          return super
        end

        if thing
          return ::FeatureFlag.vexi.unsafe_enabled?(name, thing)
        end
        return FeatureFlag.vexi.unsafe_enabled?(name)
      end

      super
    end
  end
end

Flipper::Feature.prepend(Flipper::VexiProxy)
