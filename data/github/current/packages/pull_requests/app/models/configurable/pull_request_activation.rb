# typed: true
# frozen_string_literal: true

# Configures whether pull requests are enabled for a repository.
module Configurable
  module PullRequestActivation
    extend ActiveSupport::Concern
    extend T::Helpers

    include ::Configurable

    requires_ancestor { PullRequestActivationConfig }

    KEY = "enable_pull_requests".freeze

    # Enable pull requests for repository.
    sig { params(actor: User).void }
    def enable_pull_requests(actor:)
      return if pull_requests_enabled?
      config.enable(KEY, actor)
      Search.add_to_search_index("bulk_pull_requests", T.must(repository.id))
      nil
    end

    # Disable pull requests for repository.
    sig { params(actor: User).void }
    def disable_pull_requests(actor:)
      return unless pull_requests_enabled?
      config.disable(KEY, actor)

      # Feature flag to control passing caller_location for bulk PR deletions
      if FeatureFlag.vexi.enabled?(:bulk_pr_es_deletion_track_caller_location, default: false)
        RemoveFromSearchIndexJob.perform_later(
          "bulk_pull_requests",
          T.must(repository.id),
          caller_location: "Repository#disable_pull_requests"
        )
      else
        RemoveFromSearchIndexJob.perform_later("bulk_pull_requests", T.must(repository.id))
      end
      nil
    end

    # Defaults to true if not set, to maintain behavior from before this was configurable.
    sig { returns(T::Boolean) }
    def pull_requests_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    rescue Configs::RpcError
      true
    end
  end
end
