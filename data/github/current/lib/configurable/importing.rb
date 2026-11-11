# typed: true
# frozen_string_literal: true

# Whether the repository is being imported.
module Configurable
  module Importing
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "is_importing".freeze

    def enable_is_importing(actor:)
      config.enable(KEY, actor)
    end

    def disable_is_importing(actor:)
      config.disable(KEY, actor)
    end

    def is_importing_enabled?
      config.enabled?(KEY)
    end
  end
end
