# typed: true
# frozen_string_literal: true

# Whether searches on dotcom are enabled
# (on GHE instances that are properly connected to dotcom)
module Configurable
  module DotcomSearch
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "dotcom_search".freeze

    def enable_dotcom_search(actor)
      config.enable(KEY, actor)
    end

    def disable_dotcom_search(actor)
      config.disable(KEY, actor)
      T.unsafe(self).disable_dotcom_private_search(actor)
    end

    def dotcom_search_enabled?
      config.enabled?(KEY)
    end
  end
end
