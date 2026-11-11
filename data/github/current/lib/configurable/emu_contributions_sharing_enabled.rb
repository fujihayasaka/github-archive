# typed: true
# frozen_string_literal: true

module Configurable
  module EmuContributionsSharingEnabled
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "emu_contributions_sharing_enabled".freeze

    def enable_emu_contributions_sharing(actor: nil)
      return unless T.unsafe(self).enterprise_managed_user_enabled?
      nil unless config.enable!(KEY, actor)
    end

    def disable_emu_contributions_sharing(actor: nil, reason: nil)
      nil unless config.delete(KEY, actor)
    end

    def emu_contributions_sharing_enabled?
      config.enabled?(KEY)
    end

    def emu_contributions_sharing_enabled_policy?
      emu_contributions_sharing_enabled? && config.inherited?(KEY)
    end
  end
end
