# typed: true
# frozen_string_literal: true

module Forks
  class ForksControlsComponent < ApplicationComponent
    sig { params(path_resolver: PathResolver).void }
    def initialize(path_resolver)
      @path_resolver = path_resolver
      @control_state = path_resolver.options
    end

    private

    attr_reader :control_state, :path_resolver
  end
end
