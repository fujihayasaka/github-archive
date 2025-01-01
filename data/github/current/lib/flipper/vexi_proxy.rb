# typed: true
# frozen_string_literal: true

# Allow GitHub features to determine if they should use Vexi or Flipper for the feature flag check.
#
# The VexiProxy module is prepended to Flipper::Feature itself

require "feature_management/feature_flag_as_flipper_actor"

module Flipper
  module VexiProxy
    # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

    # Read methods

    def enabled?(thing = nil)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enabled",
          "proxy_module:vexi",
          "actor_present:#{!thing.nil?}",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi.enabled_or_raise?(name, thing) if thing
        return FeatureFlag.vexi.enabled_or_raise?(name)
      end

      super
    end

    def percentage_of_actors_value
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:percentage_of_actors_value",
          "proxy_module:vexi",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi.percentage_of_actors_value_or_raise(name)
      end

      super
    end

    def percentage_of_time_value
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:percentage_of_time_value",
          "proxy_module:vexi",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi.percentage_of_calls_value_or_raise(name)
      end

      super
    end

    def actors_value
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:actors_value",
          "proxy_module:vexi",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        actors = FeatureFlag.vexi.actors_value_or_raise(name)
        return Set.new(actors)
      end

      super
    end

    def off?
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:off",
          "proxy_module:vexi",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi.fully_disabled_or_raise?(name)
      end

      super
    end

    def on?
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:on",
          "proxy_module:vexi",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi.fully_enabled_or_raise?(name)
      end

      super
    end

    def state
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:state",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    def conditional?
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:conditional",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    def groups_value
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:groups_value",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    def boolean_value
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:boolean_value",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    # Write methods

    def add
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:add",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    def remove
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:remove",
          "proxy_module:none",
          "call_proxied:false",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      super
    end

    def disable(thing = false)
      T.bind(self, T.untyped)

      supported_thing = is_boolean?(thing) || is_actor?(thing)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:disable",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect && supported_thing}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect && supported_thing
        return FeatureFlag.vexi_management.disable_feature_flag(name) if is_boolean?(thing)
        return FeatureFlag.vexi_management.remove_feature_flag_actors(name, [thing]) if is_actor?(thing)
      end

      super
    end

    def disable_actor(actor)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:disable_actor",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.remove_feature_flag_actors(name, [actor])
      end

      super
    end

    def disable_group(group)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:disable_group",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.remove_feature_flag_custom_gate(name, group)
      end

      super
    end

    def disable_percentage_of_actors
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:disable_percentage_of_actors",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(name, 0.0)
      end

      super
    end

    def disable_percentage_of_time
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:disable_percentage_of_time",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.set_feature_flag_percentage_of_calls(name, 0.0)
      end

      super
    end

    def enable(thing = true)
      T.bind(self, T.untyped)

      supported_thing = is_boolean?(thing) || is_actor?(thing)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enable",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect && supported_thing}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect && supported_thing
        return FeatureFlag.vexi_management.enable_feature_flag(name) if is_boolean?(thing)
        return FeatureFlag.vexi_management.add_feature_flag_actors(name, [thing]) if is_actor?(thing)
      end

      super
    end

    def enable_actor(actor)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enable_actor",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.add_feature_flag_actors(name, [actor])
      end

      super
    end

    def enable_group(group)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enable_group",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.add_feature_flag_custom_gate(name, group)
      end

      super
    end

    def enable_percentage_of_actors(percentage)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enable_percentage_of_actors",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(name, percentage.to_f)
      end

      super
    end

    def enable_percentage_of_time(percentage)
      T.bind(self, T.untyped)

      if !GitHub::AppEnvironment.test? && !ENV["GITHUB_CI"]
        tags = [
          "feature_flag_name:#{name}",
          "code.function:enable_percentage_of_time",
          "proxy_module:vexi_management",
          "call_proxied:#{GitHub.use_flipper_vexi_proxy_redirect}",
        ]
        GitHub.dogstats.increment("gh.vexi.proxy.count", tags: tags)
      end

      if GitHub.use_flipper_vexi_proxy_redirect
        return FeatureFlag.vexi_management.set_feature_flag_percentage_of_calls(name, percentage.to_f)
      end

      super
    end

    private

    def is_boolean?(thing)
      return false if thing.nil?
      thing.is_a?(TrueClass) || thing.is_a?(FalseClass)
    end

    def is_actor?(thing)
      return false if thing.nil?
      thing.respond_to?(:flipper_id) || thing.respond_to?(:vexi_id)
    end
    # rubocop:enable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    # rubocop:enable GitHub/FeatureManagement/NoVexiManagementUsage
    # rubocop:enable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end
end

Flipper::Feature.prepend(Flipper::VexiProxy)
