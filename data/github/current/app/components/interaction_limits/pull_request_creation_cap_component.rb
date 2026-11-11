# typed: true
# frozen_string_literal: true

module InteractionLimits
  class PullRequestCreationCapComponent < ApplicationComponent
    attr_reader :repo

    def initialize(repository)
      @repo = repository
    end

    def bypass_list_enabled?
      FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist, repo, default: false)
    end
  end
end
