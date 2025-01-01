# typed: true
# frozen_string_literal: true

# Allow GitHub features to determine if they should use Vexi or Flipper for the feature flag check.
#
# The VexiProxy module is prepended to Flipper::Feature itself

require "feature_management/feature_flag_as_flipper_actor"

module Flipper
  module VexiProxy

    def enabled?(thing = nil)
      T.bind(self, T.untyped)

      if GitHub.use_flipper_vexi_proxy_redirect
        return ::FeatureFlag.vexi.enabled_or_raise?(name, thing) if thing # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        return ::FeatureFlag.vexi.enabled_or_raise?(name) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end

      super
    end
  end
end

Flipper::Feature.prepend(Flipper::VexiProxy)
