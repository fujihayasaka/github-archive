# typed: true
# frozen_string_literal: true

module Forks
  class ForksListingComponent < ApplicationComponent
    attr_reader :path_resolver, :forks

    sig do
      params(
        forks: T::Array[Repository],
        attributes: T::Hash[Symbol, T.untyped],
        path_resolver: Forks::PathResolver,
      ).void
    end
    def initialize(forks, attributes, path_resolver)
      @forks = forks
      @attributes = attributes
      @path_resolver = path_resolver
    end

    private

    def detail_components
      @forks.map { |f| Forks::ForkDetailComponent.new(f, @attributes) }
    end

    def render?
      # The last_updated attributes should exist for fork we're meant
      # to render (even if the value is nil, the key will exist).
      # Therefore if there is nothing in the :last_updated hash,
      # then there's nothing to render.
      # This is an alternative to `forks.any?` which generates an unnecessary query.
      @attributes[:last_updated].any?
    end
  end
end
