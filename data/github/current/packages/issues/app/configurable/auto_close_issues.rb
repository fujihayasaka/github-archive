# typed: true
# frozen_string_literal: true

# Configures whether to allow auto-closing issues when a linked pull request is merged for a repository.
module AutoCloseIssues
  module Configurable
    extend ActiveSupport::Concern
    extend T::Helpers

    include ::Configurable

    requires_ancestor { AutoCloseIssuesConfig }

    KEY = "auto_close_issues".freeze

    # Allow auto-close for repository.
    def allow_auto_close(actor:)
      return if auto_close_allowed?

      config.enable(KEY, actor)
    end

    # Disallow auto-close for repository.
    def disallow_auto_close(actor:)
      return unless auto_close_allowed?

      config.disable(KEY, actor)
    end

    # Defaults to true if not set, to maintain behavior from before this was configurable.
    def auto_close_allowed?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
