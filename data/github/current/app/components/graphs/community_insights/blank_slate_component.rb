# typed: true
# frozen_string_literal: true

module Graphs
  module CommunityInsights
    class BlankSlateComponent < ApplicationComponent
      attr_reader :repository

      def initialize(repository:)
        @repository = repository
      end
    end
  end
end
