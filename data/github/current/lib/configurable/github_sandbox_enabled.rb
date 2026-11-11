# typed: strict
# frozen_string_literal: true

module Configurable
  module GithubSandboxEnabled
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "github_sandbox_enabled"
    # Ruby-only flag: never written to by the Go service.
    # Tracks whether the enterprise is in "Enabled for all orgs" mode, which is
    # distinct from "Let orgs decide" even though both set github_sandbox_enabled
    # to "all_members" on the enterprise row.
    ALL_ORGS_MODE_KEY = "github_sandbox_all_orgs_enabled"

    ALL_MEMBERS = "all_members"
    DISABLED = "disabled"
    DEFAULT = DISABLED

    CONFIG_TYPES = T.let([ALL_MEMBERS, DISABLED].freeze, T::Array[String])

    sig { returns(String) }
    def github_sandbox_enabled_setting
      # Use direct lookup to avoid cascading the enterprise-level setting down to child orgs.
      # At the enterprise level, ALL_MEMBERS means "let orgs decide"; at the org level it
      # means "enabled for all members" — so inheriting the value would produce the wrong
      # default radio-button selection when the org has never explicitly saved a preference.
      T.unsafe(self).configuration_entries.find_by(name: KEY)&.value || DEFAULT
    end

    sig { returns(T::Boolean) }
    def github_sandbox_enabled?
      github_sandbox_enabled_setting == ALL_MEMBERS
    end

    sig { returns(T::Boolean) }
    def github_sandbox_disabled?
      github_sandbox_enabled_setting == DISABLED
    end

    sig { params(value: String, actor: User, force: T::Boolean).returns(T::Boolean) }
    def update_github_sandbox_enabled(value, actor:, force: false)
      raise ArgumentError, "invalid sandbox setting: #{value}" unless CONFIG_TYPES.include?(value)

      config.set!(KEY, value, actor, force)
    end

    # Returns true when this enterprise has the "Enabled for all orgs" mode active.
    # Only meaningful on a Business; orgs never have this key set.
    sig { returns(T::Boolean) }
    def github_sandbox_all_orgs_mode?
      config.enabled?(ALL_ORGS_MODE_KEY)
    end

    sig { params(enabled: T::Boolean, actor: User).void }
    def update_github_sandbox_all_orgs_mode(enabled, actor:)
      if enabled
        config.enable!(ALL_ORGS_MODE_KEY, actor)
      else
        config.disable!(ALL_ORGS_MODE_KEY, actor)
      end
    end
  end
end
