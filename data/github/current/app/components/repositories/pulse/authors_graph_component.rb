# typed: true
# frozen_string_literal: true

module Repositories
  module Pulse
    class AuthorsGraphComponent < ApplicationComponent
      def initialize(repository:, period: nil)
        @repository, @period = repository, period
      end
    end
  end
end
