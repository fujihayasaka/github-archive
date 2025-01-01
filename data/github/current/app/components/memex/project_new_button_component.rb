# typed: true
# frozen_string_literal: true

module Memex
  class ProjectNewButtonComponent < ApplicationComponent
    attr_reader :new_memex_path, :classes

    def initialize(new_memex_path:, classes: "")
      @new_memex_path = new_memex_path
      @classes = classes
    end
  end
end
