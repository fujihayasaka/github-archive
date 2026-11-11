# typed: true
# frozen_string_literal: true

# Configures whether commit comments are enabled for a repository.
module Configurable
  module CommitComments
    extend ActiveSupport::Concern
    extend T::Helpers

    include ::Configurable

    requires_ancestor { CommitCommentsConfig }

    KEY = "commit_comments".freeze

    # Enable commit comments for repository.
    def enable_commit_comments(actor:)
      return if commit_comments_enabled?
      config.enable(KEY, actor)
    end

    # Disable commit comments for repository.
    def disable_commit_comments(actor:)
      return unless commit_comments_enabled?
      config.disable(KEY, actor)
    end

    # Defaults to true if not set, to maintain behavior from before this was configurable.
    sig { returns T::Boolean }
    def commit_comments_enabled?
      return true unless FeatureFlag.vexi.enabled?(:configure_commit_comments, repository, default: false)
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
