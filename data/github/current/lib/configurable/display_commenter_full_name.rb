# typed: true
# frozen_string_literal: true

module Configurable
  module DisplayCommenterFullName
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "enable_display_commenter_full_name".freeze

    def enable_display_commenter_full_name(force: false, actor:)
      changed = if force
        config.enable!(KEY, actor, force)
      else
        config.enable(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("display_commenter_full_name_enable")
      GitHub.instrument("display_commenter_full_name_enabled", instrumentation_payload(actor))
      T.unsafe(self).instrument("display_commenter_full_name_enabled", instrumentation_payload(actor))
    end

    def disable_display_commenter_full_name(force: false, actor:)
      changed = config.disable!(KEY, actor, force)
      return unless changed
      GitHub.dogstats.increment("display_commenter_full_name_disable")
      GitHub.instrument("display_commenter_full_name_disabled", instrumentation_payload(actor))
      T.unsafe(self).instrument("display_commenter_full_name_disabled", instrumentation_payload(actor))
    end

    def display_commenter_full_name_setting_enabled?
      config.enabled?(KEY)
    end

    def display_commenter_full_name_enforced?
      config.final?(KEY)
    end

    private def instrumentation_payload(actor)
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
