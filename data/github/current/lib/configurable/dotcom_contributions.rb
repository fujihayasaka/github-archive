# typed: true
# frozen_string_literal: true

# Whether linking dotcom and enterprise accounts for contribution counting is enabled
# (on GHE instances that are properly connected to dotcom)
module Configurable
  module DotcomContributions
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "dotcom_contributions".freeze

    def enable_dotcom_contributions(actor)
      config.enable(KEY, actor)
    end

    def disable_dotcom_contributions(actor)
      config.disable(KEY, actor)
    end

    def dotcom_contributions_enabled?
      config.enabled?(KEY)
    end
  end
end
