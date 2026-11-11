# typed: true
# frozen_string_literal: true

# Is org creation permitted to users who are _not_ enterprise owners?
#
# Disabled by default on new installations. Was previously enabled by default.
# See https://github.com/github/admin-experience/issues/1411
#
# Note to avoid confusion:
#
# It's not that intuitive, but for historical reasons the key used here is
# `disable_user_org_creation`, which gets _enabled_ (value set to "true") to
# _disable_ org creation and gets _disabled_ (value set to "false") to _enable_
# org creation.
module Configurable
  module OrgCreation
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "disable_user_org_creation".freeze

    def enable_org_creation(actor)
      config.disable(KEY, actor)
    end

    def disable_org_creation(actor)
      config.enable(KEY, actor)
    end

    def org_creation_enabled?
      # Default to disabled if the setting has never been set.
      return false if config.get(KEY).nil?

      !config.enabled?(KEY)
    end
  end
end
