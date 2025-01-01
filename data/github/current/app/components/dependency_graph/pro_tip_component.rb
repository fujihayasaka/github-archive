# typed: true
# frozen_string_literal: true

module DependencyGraph
  class ProTipComponent < ApplicationComponent
    sig { returns T.nilable(Repository) }
    attr_reader :repo

    def initialize(repo:)
      @repo = repo
    end

    def render?
      repo&.feature_enabled?(:dependency_graph_npm_dgp_repo_insights) || repo&.owner&.feature_enabled?(:dependency_graph_npm_dgp_repo_insights)
    end
  end
end
