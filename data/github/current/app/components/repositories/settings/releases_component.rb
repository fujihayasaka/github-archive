# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class ReleasesComponent < ApplicationComponent
      attr_reader :repo

      def initialize(repository)
        @repo = repository
      end

      sig { returns(::Releases::ImmutableRepositoryConfig) }
      memoize def config
        Releases::ImmutableRepositoryConfig.new(repo)
      end
    end
  end
end
