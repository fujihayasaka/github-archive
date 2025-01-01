# typed: false
# frozen_string_literal: true

module Configurable
  module PackagesCanInheritAccessFromRepo
    INHERIT_ACCESS_METRICS_PREFIX = "inherit_packages_access_from_repo"
    INHERIT_ACCESS_KEY = "inherit_packages_access_from_repo_enabled"

    def allow_packages_to_inherit_access_from_repo(actor:)
      changed = config.enable!(INHERIT_ACCESS_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{INHERIT_ACCESS_METRICS_PREFIX}.enable")
      GitHub.instrument(
        "#{INHERIT_ACCESS_METRICS_PREFIX}.enable",
        publishing_instrumentation_payload(actor))
    end

    def disallow_packages_to_inherit_access_from_repo(actor:)
      changed = config.disable!(INHERIT_ACCESS_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{INHERIT_ACCESS_METRICS_PREFIX}.disable")
      GitHub.instrument(
        "#{INHERIT_ACCESS_METRICS_PREFIX}.disable",
        publishing_instrumentation_payload(actor))
    end

    def clear_packages_to_inherit_access_from_repo_setting(actor:)
      changed = config.delete(INHERIT_ACCESS_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{INHERIT_ACCESS_METRICS_PREFIX}.clear")
      GitHub.instrument(
        "#{INHERIT_ACCESS_METRICS_PREFIX}.clear",
        publishing_instrumentation_payload(actor))
    end

    def packages_can_inherit_access_from_repo?
      # We want to default to true if the setting is not set
      return true unless config.local?(INHERIT_ACCESS_KEY)
      config.enabled?(INHERIT_ACCESS_KEY)
    end

    private

    def publishing_instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
