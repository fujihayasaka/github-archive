# typed: true
# frozen_string_literal: true

module Releases
  class SubnavComponent < ApplicationComponent
    def initialize(repository, selected: nil, classes: "")
      @repository = repository
      @classes = classes
      @selected = selected
    end

    attr_reader :repository, :classes, :selected
  end
end
