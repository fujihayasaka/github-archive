# typed: true
# frozen_string_literal: true

# Whether Dependabot is given permission to access public dotcom repositories
# (on GHE instances that are properly connected to dotcom)
module Configurable
  module GheDependabotAccessToDotcom
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "ghe_dependabot_access_to_dotcom"

    def enable_ghe_dependabot_access_to_dotcom(actor)
      config.enable(KEY, actor)
    end

    def disable_ghe_dependabot_access_to_dotcom(actor)
      config.disable(KEY, actor)
    end

    def ghe_dependabot_access_to_dotcom_enabled?
      config.enabled?(KEY)
    end
  end
end
