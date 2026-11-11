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
      RemoveFromSearchIndexJob.perform_later("bulk_pull_requests", T.must(repository.id))
      nil
    end

    # Defaults to true if not set, to maintain behavior from before this was configurable.
    sig { returns(T::Boolean) }
    def pull_requests_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
