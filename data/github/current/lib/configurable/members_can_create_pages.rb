# typed: false
# frozen_string_literal: true

module Configurable
  module MembersCanCreatePages

    # `global` is used by the first iteration of Pages org toggle, where it is either on or off
    # The second iteration adds the ability to enable/disable public/private pages separately
    METRICS_PREFIX = {
      global: "members_can_create_pages",
      public: "members_can_create_public_pages",
      private: "members_can_create_private_pages",
    }

    KEY = {
      global: "members_can_create_pages",
      public: "members_can_create_public_pages",
      private: "members_can_create_private_pages",
    }

    ### Global Toggle

    def allow_members_to_create_pages(force: false, actor:)
      changed = if force
        # since the default is true, enabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.enable!(KEY[:global], actor, force)
      else
        config.delete(KEY[:global], actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:global]}", tags: ["status:enabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:global]}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_creating_pages(force: false, actor:)
      changed = config.disable!(KEY[:global], actor, force)
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:global]}", tags: ["status:disabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:global]}.disable",
        publishing_instrumentation_payload(actor))
    end

    def members_can_create_pages?
      # return true unless the key is set to true. Key not being set at all
      # defaults to true
      #
      # for new version of the toggle, either public or private pages is enabled for pages to be considered to be enabled
      # use '&&' here they are by default enabled

      if self.is_emu?
        (config.get(KEY[:global]).nil? || config.enabled?(KEY[:global])) \
        && (config.get(KEY[:private]).nil? || config.enabled?(KEY[:private]))
      else
        (config.get(KEY[:global]).nil? || config.enabled?(KEY[:global])) \
        && (config.get(KEY[:public]).nil? || config.enabled?(KEY[:public]) || config.get(KEY[:private]).nil? || config.enabled?(KEY[:private]))
      end
    end

    def update_members_create_pages_permission(enabled:, actor:)
      enabled ? allow_members_to_create_pages(actor: actor) : block_members_from_creating_pages(actor: actor)
    end

    def delete_members_can_create_pages_config
      # if we are using the public and private configs, the global one is no longer needed
      config.delete(KEY[:global], actor) if config.get(KEY[:global]).present?
    end

    ### Public Visibility

    def allow_members_to_create_public_pages(force: false, actor:)
      # Skip for EMU
      return if self.is_emu?

      delete_members_can_create_pages_config

      changed = if force
        # since the default is true, enabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.enable!(KEY[:public], actor, force)
      else
        config.delete(KEY[:public], actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:public]}", tags: ["status:enabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:public]}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_creating_public_pages(force: false, actor:)
      # Skip for EMU
      return if self.is_emu?

      delete_members_can_create_pages_config

      changed = config.disable!(KEY[:public], actor, force)
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:public]}", tags: ["status:disabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:public]}.disable",
        publishing_instrumentation_payload(actor))
    end

    def members_can_create_public_pages?
      # return true unless the key is set to true. Key not being set at all
      # defaults to true
      #
      # if it is globally disabled, consider creating public pages disabled

      # EMU can never create public pages sites
      return false if self.is_emu?

      # Lookup config entries (public then global)
      (config.get(KEY[:public]).nil? || config.enabled?(KEY[:public])) \
        && (config.get(KEY[:global]).nil? || config.enabled?(KEY[:global]))
    end

    def update_members_create_public_pages_permission(enabled:, actor:)
      enabled ? allow_members_to_create_public_pages(actor: actor) : block_members_from_creating_public_pages(actor: actor)
    end

    ### Private Visibility

    def allow_members_to_create_private_pages(force: false, actor:)
      delete_members_can_create_pages_config

      changed = if force
        # since the default is true, enabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.enable!(KEY[:private], actor, force)
      else
        config.delete(KEY[:private], actor)
      end
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:private]}", tags: ["status:enabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:private]}.enable",
        publishing_instrumentation_payload(actor))
    end

    def block_members_from_creating_private_pages(force: false, actor:)
      delete_members_can_create_pages_config

      changed = config.disable!(KEY[:private], actor, force)
      return unless changed

      GitHub.dogstats.increment("#{METRICS_PREFIX[:private]}", tags: ["status:disabled"])
      GitHub.instrument(
        "#{METRICS_PREFIX[:private]}.disable",
        publishing_instrumentation_payload(actor))
    end

    def members_can_create_private_pages?
      # return true unless the key is set to true. Key not being set at all
      # defaults to true
      #
      # if it is globally disabled, consider creating private pages disabled
      (config.get(KEY[:private]).nil? || config.enabled?(KEY[:private])) \
        && (config.get(KEY[:global]).nil? || config.enabled?(KEY[:global]))
    end

    def update_members_create_private_pages_permission(enabled:, actor:)
      enabled ? allow_members_to_create_private_pages(actor: actor) : block_members_from_creating_private_pages(actor: actor)
    end

    private

    # Is the current scope, EMU?
    def is_emu?
      if self.is_a?(Organization)
        return self.async_enterprise_managed_user_enabled?.sync
      elsif self.is_a?(Business)
        # Note that we don't support YET Pages policies on enterprises (i.e. businesses).
        return self.enterprise_managed_user_enabled?
      end
      false
    end

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
