# typed: true
# frozen_string_literal: true

module Configurable
  module CommitComments
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }
    requires_ancestor { GitHub::VexiActor }

    KEY = "commit_comments".freeze

    # Enable commit comments for a repository.
    def enable_commit_comments(actor:)
      raise ArgumentError, "can only be configured on a Repository" unless self.is_a?(Repository)

      config.enable(KEY, actor)
    end

    # Disable commit comments for a repository.
    def disable_commit_comments(actor:)
      raise ArgumentError, "can only be configured on a Repository" unless self.is_a?(Repository)

      config.disable(KEY, actor)
    end

    # Reset a user's or organization's default to enable commit comments.
    def enable_commit_comments_by_default(actor:)
      raise ArgumentError, "can only be configured on a User or Organization" unless self.is_a?(User)

      config.delete(KEY, actor)
    end

    # Set a user's or organization's default to disable commit comments.
    def disable_commit_comments_by_default(actor:)
      raise ArgumentError, "can only be configured on a User or Organization" unless self.is_a?(User)

      config.disable(KEY, actor)
    end

    # Defaults to true if not set, to maintain behavior from before this was configurable.
    def commit_comments_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
