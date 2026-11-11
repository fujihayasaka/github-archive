# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class CommitCommentsComponent < ApplicationComponent
      attr_reader :repo

      def initialize(repository)
        @repo = repository
      end
    end
  end
end
