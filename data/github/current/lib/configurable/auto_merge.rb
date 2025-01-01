# typed: true
# frozen_string_literal: true

# Configures whether to allow/display auto-merge for a repository
module Configurable
  module AutoMerge
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }

    KEY = "auto_merge".freeze

    # Allow auto-merge for repository.
    def allow_auto_merge(actor:)
      return if auto_merge_allowed?

      config.enable(KEY, actor)
    end

    # Disallow auto-merge for repository.
    def disallow_auto_merge(actor:)
      return unless auto_merge_allowed?

      config.disable(KEY, actor)
    end

    def auto_merge_allowed?
      config.enabled?(KEY)
    end
    async_configurable :auto_merge_allowed?
  end
end
