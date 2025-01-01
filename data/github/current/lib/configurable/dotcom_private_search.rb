# typed: true
# frozen_string_literal: true

# Whether searches on dotcom include private results from the org
# (on GHE instances that are properly connected to dotcom)
module Configurable
  module DotcomPrivateSearch
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "dotcom_private_search".freeze

    def enable_dotcom_private_search(actor)
      config.enable(KEY, actor)
    end

    def disable_dotcom_private_search(actor)
      config.disable(KEY, actor)
    end

    def dotcom_private_search_enabled?
      config.enabled?(KEY)
    end
  end
end
