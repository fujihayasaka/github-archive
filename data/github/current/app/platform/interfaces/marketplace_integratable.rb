# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module MarketplaceIntegratable
      include Platform::Interfaces::Base
      description "An object that can be listed in the GitHub Marketplace."
      visibility :internal

      field :preferred_background_color, String,
        null: false,
        description: "The hex color code for the background color this object's icon should be displayed on.",
        method: :async_preferred_bgcolor,
        visibility: :internal
    end
  end
end
