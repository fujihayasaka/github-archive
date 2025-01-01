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
      # Transitive dependencies are not available from Dependency Graph in enterprise
      !GitHub.enterprise?
    end
  end
end
