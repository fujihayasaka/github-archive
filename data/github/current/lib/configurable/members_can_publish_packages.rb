# typed: false
# frozen_string_literal: true

module Configurable
  module MembersCanPublishPackages
    PUBLIC_METRICS_PREFIX = "publish_public_packages"
    PUBLIC_KEY = "publish_public_packages_enabled"

    INTERNAL_METRICS_PREFIX = "publish_internal_packages"
    INTERNAL_KEY = "publish_internal_packages_enabled"

    PRIVATE_METRICS_PREFIX = "publish_private_packages"
    PRIVATE_KEY = "publish_private_packages_enabled"

    # PRIVATE_VISIBILITY

    def allow_members_to_publish_private_packages(force: false, actor:)
      changed = config.enable!(PRIVATE_KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("#{PRIVATE_METRICS_PREFIX}.enable")
      GitHub.instrument(
        "#{PRIVATE_METRICS_PREFIX}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_publishing_private_packages(force: false, actor:)
      changed = if force
        config.disable!(PRIVATE_KEY, actor, force)
      else
        config.delete(PRIVATE_KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{PRIVATE_METRICS_PREFIX}.disable")
      GitHub.instrument(
        "#{PRIVATE_METRICS_PREFIX}.disable",
        publishing_instrumentation_payload(actor))
    end

    def clear_publish_private_packages_setting(actor:)
      changed = config.delete(PRIVATE_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{PRIVATE_METRICS_PREFIX}.clear")
      GitHub.instrument(
        "#{PRIVATE_METRICS_PREFIX}.clear",
        publishing_instrumentation_payload(actor))
    end

    def members_can_publish_private_packages?
      true
    end

    # INTERNAL_VISIBILITY

    def allow_members_to_publish_internal_packages(force: false, actor:)
      changed = config.enable!(INTERNAL_KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("#{INTERNAL_METRICS_PREFIX}.enable")
      GitHub.instrument(
        "#{INTERNAL_METRICS_PREFIX}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_publishing_internal_packages(force: false, actor:)
      changed = if force
        config.disable!(INTERNAL_KEY, actor, force)
      else
        config.delete(INTERNAL_KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{INTERNAL_METRICS_PREFIX}.disable")
      GitHub.instrument(
        "#{INTERNAL_METRICS_PREFIX}.disable",
        publishing_instrumentation_payload(actor))
    end

    def clear_publish_internal_packages_setting(actor:)
      changed = config.delete(INTERNAL_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{INTERNAL_METRICS_PREFIX}.clear")
      GitHub.instrument(
        "#{INTERNAL_METRICS_PREFIX}.clear",
        publishing_instrumentation_payload(actor))
    end

    def members_can_publish_internal_packages?
      config.enabled?(INTERNAL_KEY)
    end

    # PUBLIC_VISIBILITY

    def allow_members_to_publish_public_packages(force: false, actor:)
      changed = config.enable!(PUBLIC_KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("#{PUBLIC_METRICS_PREFIX}.enable")
      GitHub.instrument(
        "#{PUBLIC_METRICS_PREFIX}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_publishing_public_packages(force: false, actor:)
      changed = if force
        config.disable!(PUBLIC_KEY, actor, force)
      else
        config.delete(PUBLIC_KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{PUBLIC_METRICS_PREFIX}.disable")
      GitHub.instrument(
        "#{PUBLIC_METRICS_PREFIX}.disable",
        publishing_instrumentation_payload(actor))
    end

    def clear_publish_public_packages_setting(actor:)
      changed = config.delete(PUBLIC_KEY, actor)
      return unless changed

      GitHub.dogstats.increment("#{PUBLIC_METRICS_PREFIX}.clear")
      GitHub.instrument(
        "#{PUBLIC_METRICS_PREFIX}.clear",
        publishing_instrumentation_payload(actor))
    end

    def members_can_publish_public_packages?
      config.enabled?(PUBLIC_KEY)
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
